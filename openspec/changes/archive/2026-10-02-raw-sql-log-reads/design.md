# Design

## Context

See proposal.md - Why for motivation. Current state and the constraints that shaped this approach, all verified against the running app on 2026-10-02:

**Why text search cannot be pushed down through Ash.** `ash_clickhouse 0.7.3` *does* implement a `:like` comparison — `deps/ash_clickhouse/lib/ash_clickhouse/data_layer/query_builder.ex:384` emits `message LIKE ?` with a bound parameter. The existing moduledoc in `filter.ex` blames the wrong layer. The real blocker is Ash 3.33.11: `deps/ash/lib/ash/query/operator/` contains only `eq`, `greater_than`, `greater_than_or_equal`, `has`, `in`, `is_nil`, `less_than`, `less_than_or_equal`, `not_eq`, `overlap`. There is no `:like`, `:contains`, or `:starts_with` operator, so Ash rejects the filter before the data layer is consulted:

```
Ash.Query.filter(like(message, ^"%timeout%"))
  -> Ash.Error.Query.NoSuchFunction{function: :like}
```

The `:like`, `:contains`, `:starts_with`, and `:ends_with` clauses in AshClickhouse's `build_comparison/3` are unreachable with this Ash version. Patching Ash to add a `:like` operator would mean owning a fork of a framework operator set — the wrong layer to patch for a dashboard.

**What the raw query path actually returns.** `ClickhouseExLogger.Repo.query/3` delegates to `AshClickhouse.Connection.query/4`, which defaults to `default_format: "JSONCompactEachRow"`. Verified live:

```
{:ok, %ClickHouse.Result{columns: nil,
                          rows: [["9f86d2ec-...", "2026-10-02 02:16:05.280004", ...]]}}
                              ^^^^^^          ^^^^^^ positional list, timestamp is a String
```

Three consequences drive the design: rows come back **positional**, not keyed; `columns` is `nil`, so the caller must know its own column order; and `timestamp` arrives as a string rather than the `DateTime` that Ash's `:utc_datetime_usec` type produces.

**The driver cannot return maps.** `deps/clickhouse/lib/clickhouse/format/` ships only `json_compact_each_row`, `row_binary`, `tsv`, `tsv_with_names`, `tsv_with_names_and_types`, and `values`. There is no `JSONEachRow` decoder, and passing `default_format: "JSONEachRow"` returns `%Result{rows: nil, columns: nil}` with **no error raised** — a silent-empty failure mode worth remembering.

**Prune already established raw SQL as this codebase's escape hatch.** `Prune.run/2` issues `ALTER TABLE ... DELETE WHERE` with bound parameters and a qualified table name derived from `Repo.config()[:database]`. The MVP design rejected this route in favor of `Ash.bulk_destroy` (design.md Decision 4) because Ash cannot stream ClickHouse reads without keyset support. The implementation reversed that decision for a good reason; this change extends the same choice to reads rather than inventing a second precedent.

## Goals / Non-Goals

**Goals:**

- One read path for the viewer, with a single row contract, so a row renders identically whether or not search is active.
- Database-evaluated wildcard search whose results are complete.
- No new dependencies and no change to DDL, ingestion, or the `logs` table.

**Non-Goals:**

- Analysis behavior. `Analysis`, `AnalysisLive.Index`, and AshDyan stay exactly as they are; the `log-analysis` delta corrects a requirement's wording only.
- Auth. Explicitly deferred past this change.
- Making `LogView` disappear. It remains the schema source of truth and the analysis resource.

## Decisions

### 1. All viewer reads go raw, not just searched ones

- What: `LogLive.Index` reads through a new raw path unconditionally. `LogView`'s `read` action is left serving `AshDyan` analysis, the seeder's shape reference, and tests.
- Why: the raw path has to exist regardless of the branch. The only thing forcing two paths is inertia — reading rows through Ash and then re-rendering them. Branching would give the viewer two row contracts, and `log_live/index.ex:159` renders `{log.timestamp}` unconditionally, so the *same row* would display `~U[2026-10-02 02:16:05.280004Z]` unsearched and `2026-10-02 02:16:05.280004` searched. That is a visible, confusing artifact of a purely internal choice.
- Alternative (raw only when `search != ""`, Ash otherwise): smaller diff and `LogView` keeps backing the viewer, at the cost of a permanent dual row contract. Rejected as the kind of complexity that looks cheap once and expensive forever.
- Trade-off accepted: the viewer no longer passes through the Ash read action, so it loses Ash-level authorization and filter plumbing it was not meaningfully using. The resource's role narrows, which is the real cost.

### 2. Derive the SELECT column list from the resource, not by hand

- What: build the projection from `Ash.Resource.Info.attributes(LoggerDashboard.Logs.LogView)`, using each attribute's name, and zip positional rows against that same list.
- Why: `design.md` Decision 1 explicitly rejected a dashboard-owned duplicate of the upstream table's DSL because two writers diverge. Hand-writing `SELECT id, timestamp, level, ...` reintroduces exactly that risk, in column-list form. Deriving from the resource keeps one source of truth while still letting the WHERE clause be hand-built.
- Alternative (hand-written column list): simpler to read, but drifts silently when upstream adds a column.

### 3. One shared predicate builder for reads and prune

- What: a single builder emits the `node` / `level` / `timestamp` predicates with bound parameters, plus `message LIKE ?` when and only when `search` is non-empty. The read path appends `ORDER BY timestamp DESC LIMIT ? OFFSET ?`; prune appends nothing.
- Why: `Prune.where_clause/2` already builds exactly the node/level/timestamp predicates from the same `%Filter{}` struct with bound params, and it is already tested. Duplicating four predicates in a new read path invites drift. Critically, prune's "never filter on message" guarantee then falls out of existing behavior for free — `Prune.parse/1:37` already normalizes `%{filter | search: ""}` — so the builder needs no special case and no second code path to keep in sync.
- Security note: every predicate is derived from already-validated `Filter` fields and every value is a bound parameter. No user input reaches the SQL string. This mirrors `Prune.where_clause/2` and must stay that way.

### 4. Decode raw rows back into the contract Ash was providing

- What: convert positional rows to atom-keyed maps with `:id` as the key (required by `stream/3`'s `dom_id/1`), parse `timestamp` from its `DateTime64(6)` string form into a `DateTime`, and convert `level` to an atom to match the resource's `:atom` type.
- Why: the template is the consumer, and it must not be able to tell which path produced a row. `level` specifically is `:atom` in `LogView`; leaving it a string would break any `log.level == :error` comparison that a future change might reasonably write.

### 5. Prune guards live in the parse boundary, not the LiveView

- What: `Prune.parse/1` rejects an absent scope and rejects a prune with neither `from` nor `to`. `PruneLive.Index` renders both as validation errors on preview.
- Why: `parse/1` is the single funnel both callers go through, so a guard placed there cannot be bypassed by a future caller. Today `Prune.parse(%{})` returns `{:ok, %Filter{}, :all}` and `where_clause/2` compiles that to `{"1 = 1", []}`; the form's `scope` default of `"node"` is the only thing preventing a full-table delete, and a UI default is not a safety property. Deleting the destructive-by-default behavior at the parse boundary means the empty-params case is rejected regardless of how the request was constructed.
- Rejected: guarding in the LiveView (bypassable), and an "unbounded prune" checkbox override. The operator who genuinely wants to wipe everything can supply a maximally wide range; a checkbox that makes the *absence* of a bound clickable re-introduces the omission risk the guard exists to remove.

### 6. Remove the code this makes dead

- What: delete `Filter.to_regex/1`, `Filter.apply_message_filter/2`, `Filter.to_query/2` (no remaining `lib/` caller — `Analysis` reaches AshDyan through `dyan_filters/1`, not `to_query/2`), `@search_fetch_limit`/`search_fetch_limit/0`, and `Filter.max_limit/0` and `Filter.levels/0`, which already had no callers outside their own definitions.
- Why: leaving them invites the next reader to believe an in-memory filter is still live. `Filter.to_like_pattern/1` stops being dead and becomes the translation it was always written for — its test at `filter_test.exs:6-20` becomes live coverage of real behavior instead of a description of an abandoned attempt.

## Risks / Trade-offs

- **Raw `LIKE` is now unbounded by the old 1,000-row cap, so a wide scope can get slow.** The in-memory path scanned at most 1,000 rows in Elixir; a pushed-down `%...%` predicate may touch many parts. Mitigation: ClickHouse reads in primary-key order (`ORDER BY timestamp`) and the query is always bounded by `LIMIT`, so a narrow window stops early; the UI already presents `from`/`to` prominently. `design.md` already carried this risk with the same mitigation and the message-index (`ngrambf`/`tokenbf`) deferral stands.
- **Two row contracts reappear if decoding drifts from what Ash produced.** Mitigated by making the decode step a single named function with a test asserting `timestamp` is a `DateTime` and `level` an atom, and by removing the Ash read path from the viewer so there is only one path to drift from.
- **`metadata` round-trips identically through both paths — verified, not assumed.** Inserted a row with `metadata: %{"env" => "prod", "request_id" => "abc-123"}` and compared both readers:

  | Path | Result |
  |---|---|
  | Ash (`Ash.read/2` on `LogView`) | `%{"env" => "prod", "request_id" => "abc-123"}` |
  | Raw (`Repo.query/3`, `SELECT metadata`) | `[%{"env" => "prod", "request_id" => "abc-123"}]` |
  | `LogRead.decode/1` output | `%{"env" => "prod", "request_id" => "abc-123"}` — equal to Ash |

  The driver wraps the raw map in a single-element list because `JSONCompactEachRow` encodes one map per row; `decode/1` unwraps it via positional zip, so the decoded value matches Ash exactly. No special handling was needed and `metadata` needs no cast in `normalize/1`.

  Note that `LogView` is unused by the viewer's projection ordering: `AshClickhouse` sorts its own SELECT columns alphabetically, while `LogRead` uses `Ash.Resource.Info.attributes/1` declaration order. Both zip against the order they requested, so this is not a correctness issue, but it means column order is a per-reader concern rather than a global one.
- **Losing the Ash read path removes a layer of indirection that was doing nothing.** Accepted; see Decision 1.
- **A silently-empty driver failure mode exists.** An unsupported `default_format` returns `rows: nil` with no error. The new read path must treat a `nil` rows field as an error rather than as "no results," or an unsupported format will present as an empty log list.
- **The `:clickhouse`-tagged tests are the only coverage for these paths** and require a running ClickHouse; `test_helper.exs` performs no exclusion, so `mix precommit` fails outright without one. Accepted for now, but any future CI work should make the tag skip rather than hard-fail.
- **Known divergence left in place, deliberately out of scope:** `log-viewing`'s row-contents requirement names `metadata` among the fields shown, and the viewer does not render it. That requirement remains inaccurate after this change. Fixing it is a UI decision (how to display a map) rather than a read-path one, so it is not bundled here.

## Migration Plan

No data migration. DDL stays owned by `clickhouse_ex_logger`; this change reads and deletes only.

1. Add the shared predicate builder and the raw read module; wire `LogLive.Index` to it.
2. Add the prune parse guards; wire `PruneLive.Index` to render the new errors.
3. Remove the dead `Filter` functions and the obsolete in-memory-search note.
4. Verify against a running ClickHouse: complete search results beyond the newest 1,000 rows, end-of-results pagination, and both prune rejections.
5. `mix precommit`.

Rollback is reverting the release. As already documented, any ClickHouse `DELETE` mutations that ran are not rolled back by a revert.

## Open Questions

- None blocking the specs, approach, or task breakdown. The `metadata` round-trip fidelity question is answered by a verification task rather than left open, because nothing currently renders it and no spec requirement depends on its shape.

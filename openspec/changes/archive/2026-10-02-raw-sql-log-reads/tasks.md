# Tasks

## 1. Shared predicate builder

- [x] 1.1 Add a predicate builder that emits `node`, `level`, and `timestamp` predicates from a validated `%Filter{}` with bound parameters, plus `message LIKE ?` only when `search` is non-empty; verify by unit test that an empty search yields no message clause, a `*timeout*` search yields `message LIKE ?` with `%timeout%`, and no predicate value is interpolated into the SQL string
- [x] 1.2 Switch `Prune.where_clause/2` to consume the shared builder and verify the existing `prune_test.exs` cases still pass unchanged, including the assertion that the generated SQL contains no `message` reference

## 2. Raw read module

- [x] 2.1 Create `LoggerDashboard.Logs.LogRead` with the `SELECT` projection derived from `Ash.Resource.Info.attributes(LoggerDashboard.Logs.LogView)` rather than hand-written; verify by test that the derived column list covers every public attribute on the resource
- [x] 2.2 Implement row decoding from positional lists to atom-keyed maps with `:id` present (required by `stream/3`'s `dom_id/1`), `timestamp` parsed to a `DateTime`, and `level` converted to an atom; verify by test against rows fetched from ClickHouse that these types match what the Ash read path previously produced
- [x] 2.3 Implement execution composing the derived projection, the shared predicates, `ORDER BY timestamp DESC`, and `LIMIT`/`OFFSET` as bound parameters; verify by an integration test that a search matching rows older than the newest 1,000 returns those rows
- [x] 2.4 Treat a `nil` `rows` field on the driver result as an error rather than as an empty result set, so an unsupported response format surfaces as a failure instead of an empty log list; verify by test that a `nil` rows result produces an error tuple

## 3. Wire the viewer to the raw read path

- [x] 3.1 Replace the `Filter.list_logs/2` call in `LoggerDashboardWeb.LogLive.Index` with the raw read path and remove the branch that swapped in-memory filtering for the searched case; verify by LiveView test that `/logs` renders rows with and without a search term present
- [x] 3.2 Remove the "applied in memory over the latest N matching rows" note and verify no such text remains in the rendered viewer
- [x] 3.3 Disable the `Next` control when a page returns fewer rows than the per-page limit and verify by LiveView test that advancing past the last page is not offered, and that the per-page size and active filters survive advancing

## 4. Prune guardrails

- [x] 4.1 Make `Prune.parse/1` reject a request carrying no scope parameter instead of defaulting to whole-system; verify by test that `Prune.parse(%{})` returns an error tuple and that the whole-system scope still works when explicitly passed
- [x] 4.2 Make `Prune.parse/1` reject a prune with neither a `from` nor a `to` bound and provide no override; verify by tests that a fully unbounded prune errors, that a one-sided range is accepted, and that the rejection names supplying a datetime range as the remedy
- [x] 4.3 Render both new validation errors in `LoggerDashboardWeb.PruneLive.Index` and verify by LiveView test that submitting an unbounded or scope-less prune shows the error and no confirmation panel

## 5. Remove code made dead

- [x] 5.1 Delete `Filter.to_regex/1`, `Filter.apply_message_filter/2`, `Filter.to_query/2`, `@search_fetch_limit`/`search_fetch_limit/0`, and the already-unused `Filter.max_limit/0` and `Filter.levels/0`; verify by compiling with `--warnings-as-errors` that no unreferenced calls or unused-attribute warnings remain
- [x] 5.2 Delete the corresponding `to_regex`/`apply_message_filter` describe blocks from `filter_test.exs` and repoint any test that exercised `Filter.to_query/2` at the new read path; verify the filtered unit suite passes without ClickHouse

## 6. Project context and final verification

- [x] 6.1 Add a `context` block to `openspec/config.yaml` recording that Ash 3.33.11 exposes no `:like` operator in `Ash.Query.Operator` — so text predicates cannot be pushed down through Ash regardless of AshClickhouse's support — and that raw SQL through `ClickhouseExLogger.Repo` is the sanctioned escape hatch; verify by reading the file back
- [x] 6.2 Verify the `metadata` round-trip: compare what `LogView` returns through Ash against what the raw read path returns for a non-empty `metadata` value, and record the finding in `design.md` without relying on an unverified shape
- [x] 6.3 Run `mix precommit` against a running ClickHouse and confirm the full suite passes, then review the rendered `/logs`, `/analysis`, and `/prune` pages to confirm analysis output is unchanged
  - `mix format` no longer crashes: added `excludes: ["**/._*"]` to `.formatter.exs` so the AppleDouble sidecars its input glob picks up are skipped. This was a pre-existing failure, reproduced on a clean stashed tree.
  - `mix precommit` runs to completion: compile-with-warnings-as-errors clean, `deps.unlock --unused` clean, format clean, `mix test` 79/80.
  - The one remaining failure is pre-existing and unrelated: `AnalysisTest "node_frequency rolls NULL into unknown"`. The shared ClickHouse holds 25,682 rows, `AshDyan` bounds reads at `max_limit` 10,000, and the NULL-node rows fall outside the sampled window, so `"unknown"` is absent from `labels`. Reproduced on a clean stashed tree. Left for a follow-up change; fixing it means scoping the analysis fixture, which is outside this change's scope.
  - Page review against live ClickHouse: `/logs` returns a full 25-row page with `has_next` true, and a `*timeout*` search returns hits with `timestamp` as `DateTime` and `level` as an atom. `/analysis` output is unchanged — levels `[debug, error, info, warning]`, 21 hourly volume buckets, 7 nodes, all still served by AshDyan through the `LogView` read action. `/prune` rejects an absent scope and an unbounded prune with their respective messages.

# Proposal

## Why

Message search on `/logs` silently returns incomplete results. Wildcard search cannot be pushed into ClickHouse through Ash, so it runs as an Elixir regex over the newest 1,000 prefiltered rows. Any match older than that 1,000-row window is invisible, and nothing in the UI says so — the failure looks like "the error never happened" rather than "the search was truncated." Pagination compounds it: past offset 1,000 the list silently empties while `Next` stays enabled, so an operator can page forever into nothing.

Alongside it, `Prune.parse/1` defaults a *missing* scope to whole-system, which compiles to `DELETE WHERE 1 = 1`. The LiveView form defaults to single-node scope so the UI never reaches it, but the function's own default is "delete every log row ever written" on the most destructive operation in the system. The MVP design promised "default to time-bounded prune"; nothing implements that.

The durable specs are also now aspirational rather than descriptive. `log-viewing` requires wildcard search "translated to a ClickHouse `LIKE`/`match` predicate" — it isn't. `log-analysis` requires per-level counts that "sum to the filtered total" — they sum to a 1,000-row sample. `log-pruning` requires a match count at confirmation — none is shown. Both archived changes landed today and the specs diverged during implementation without being revised, so anyone reading `openspec/specs/` to learn the system's contract is misled about the one guarantee that matters most for a log tool: search completeness.

## What Changes

- **BREAKING**: move the log viewer's read path off the Ash read action onto raw SQL through `ClickhouseExLogger.Repo`, so wildcard `LIKE` on `message` is pushed to ClickHouse and results are complete. This is the same escape hatch `Prune` already uses.
- Serve *all* viewer reads through that one raw path rather than branching on whether search is active. A second read path would give the same row two shapes and make timestamp rendering depend on whether the search box happens to be filled in.
- Derive the raw `SELECT` column list from `Ash.Resource.Info.attributes/1` on `LoggerDashboard.Logs.LogView` so the resource stays the single schema source, honoring the MVP's anti-drift intent.
- Decode raw rows (`timestamp` string to `DateTime`, `level` string to atom, positional rows to atom-keyed maps) into the same shape the Ash path produced, so the viewer has exactly one row contract.
- Extract a shared predicate builder that emits `node`/`level`/`timestamp` (and `message LIKE ?` only when search is non-empty) with bound parameters, consumed by both the read path and prune. Prune's existing "never filter on message" guarantee then falls out of its `search: ""` normalization instead of a special case.
- Add prune guardrails: reject a prune with no explicit scope instead of defaulting to whole-system, and reject an unbounded prune (no `from` and no `to`) outright rather than compiling it to `1 = 1`.
- Remove code left dead by the above: `Filter.to_regex/1`, `Filter.apply_message_filter/2`, `Filter.to_query/2` (no remaining `lib/` caller once viewing is raw), `@search_fetch_limit`/`search_fetch_limit/0`, and the already-unused `Filter.max_limit/0` and `Filter.levels/0`. `Filter.to_like_pattern/1` stops being dead and becomes the translation it was written for.
- Remove the now-false "applied in memory over the latest 1000 matching rows" note from the viewer, and disable `Next` when a page returns short.
- Correct three spec requirements that assert behavior the system does not have (see Capabilities).

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `log-viewing`: wildcard text search becomes a genuine ClickHouse `LIKE` predicate evaluated against all matching rows rather than an in-memory pass over the newest 1,000. This makes the existing requirement text true; the delta additionally requires that the viewer not present a truncated page as a complete one.
- `log-pruning`: adds requirements that prune rejects a missing scope and rejects an unbounded prune, instead of defaulting either to whole-system deletion.
- `log-analysis`: corrects the bounded-analysis requirement. The system aggregates over a bounded sample and discloses it; it does not produce counts that sum to the filtered total. Requirement text is corrected to describe the bound truthfully. **Analysis behavior is unchanged by this change** — only the requirement stops overclaiming.

## Impact

- **New module**: `LoggerDashboard.Logs.LogRead` owning the raw `SELECT`, column derivation, row decoding, and execution. `Filter` narrows to parse-and-validate, which is its actual job.
- **Modified**: `LoggerDashboard.Logs.Filter` (predicate builder replaces the Ash query builder; dead functions removed), `LoggerDashboard.Logs.Prune` (shares the predicate builder; adds scope and bounds guards), `LoggerDashboardWeb.LogLive.Index` (raw read, removes the in-memory-search note, pagination end detection), `PruneLive.Index` (renders the two new validation errors).
- **Unchanged**: `LoggerDashboard.Logs.LogView` keeps its attributes and remains the schema source of truth; its `read` action now serves only `AshDyan` analysis, the seeder, and tests. `Analysis` and `AnalysisLive.Index` are untouched. No new dependencies — `ClickHouse.query/3` via `ClickhouseExLogger.Repo.query/3` is already the established mechanism.
- **Project config**: `openspec/config.yaml` gains a `context` block recording that Ash 3.33.11 has no `:like` operator in `Ash.Query.Operator`, which is why text predicates cannot be pushed down through Ash regardless of AshClickhouse support, and that raw SQL through the repo is the sanctioned escape hatch.
- **Data**: none. Reads and deletes only; DDL stays owned by `clickhouse_ex_logger`.
- **Tests**: the `:clickhouse`-tagged suite is the only coverage that exercises these paths and requires a running ClickHouse; new cases cover the shared predicate builder, row decoding, the paging end, and both prune rejections.

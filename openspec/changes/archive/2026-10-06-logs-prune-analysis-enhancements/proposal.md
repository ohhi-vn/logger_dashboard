# Proposal

## Why

Operators cannot tell how large a filtered log result is (Logs page shows only `Offset/Limit` with no total), cannot see what a manual prune will delete before confirming (preview states only the resolved scope text), and cannot move an investigation from Logs to Analysis without retyping filters — while Analysis itself ignores the `search` keyword that drove the Logs result.

## What Changes

- Logs page shows the total number of rows matching the active filters (node, search, datetime-range, level), kept consistent with the page rows, `has_next` logic, and export scope.
- Manual prune preview shows what would be deleted before confirm: the matching-row count plus a small bounded sample of newest rows, derived from the same validated filter that the delete executes; preview clears on any param change and confirm still requires an explicit preview.
- Logs page offers a handoff action (e.g. "Analyze these filters") that navigates to `/analysis` carrying the active `node`, `search`, `from`, `to`, `level` (and `bucket` default), so Analysis opens on the same scope without retyping.
- Analysis page accepts and applies the `search` keyword alongside node/range/level, so level mix, volume-over-time, and per-node counts reflect the keyword-filtered scope; bound/limit disclosure and rejected-request-clears-results semantics are preserved.

## Capabilities

### New Capabilities

- None. All behavior extends existing viewer/prune/analysis scopes.

### Modified Capabilities

- `log-viewing`: total matching-row count for the active filters on the Logs page; Logs-to-Analysis handoff link carrying active filters.
- `log-pruning`: manual-prune preview must include matching-row count and bounded sample rows before confirm.
- `log-analysis`: accept `search` keyword filter and apply it to all three analyses; accept handoff params from Logs page.

## Impact

- `LoggerDashboard.Logs.LogRead` (new `count_logs/1` and bounded sample read reusing `Filter.predicates/1` with bound params), `LoggerDashboard.Logs.Analysis` (keyword-aware aggregations; raw SQL `LIKE` path since Ash 3.33 has no `:like` operator), `LoggerDashboard.Logs.Filter` (`search` passthrough for prune/analysis params).
- `LoggerDashboardWeb.LogLive.Index`, `PruneLive.Index`, `AnalysisLive.Index` templates, URL param handling, and node/level option behavior (unchanged semantics, new total/preview/handoff/search UI).
- No DDL change (table stays upstream); no new deps. Extra `COUNT(*)` + sample queries per Logs/prune-preview render and heavier keyword-filtered analysis queries — all bounded and parameterized.

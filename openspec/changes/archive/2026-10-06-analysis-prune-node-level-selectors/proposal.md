# Proposal

## Why

The logs page now offers clickable node and level selectors, but Analysis and Prune still require hand-typed `node@host` names and level values. Operators analyzing or pruning a node must copy the exact name from elsewhere, with no discovery and inconsistent interaction across the three pages.

## What Changes

- Analysis page: fetch distinct node values and render them as clickable toggles with the same multi-select semantics as the logs page (click toggles in/out, empty = all nodes); render levels as clickable single-select options.
- Prune page: fetch distinct node values and render them as clickable options that select the single-node scope (click replaces the node value and sets scope to `node`); render levels as clickable single-select options.
- Both pages keep their existing text inputs as fallback, preserve all other active filters on click, and keep their confirmation/safety behavior unchanged.

## Capabilities

### New Capabilities

- None — all behavior extends the existing pages.

### Modified Capabilities

- `log-analysis`: node selector becomes a clickable distinct-node list with logs-page toggle semantics; level selector becomes clickable.
- `log-pruning`: node selector gains clickable distinct-node options that select the single-node scope; level selector becomes clickable.

## Impact

- `LoggerDashboardWeb.AnalysisLive.Index` and `LoggerDashboardWeb.PruneLive.Index` templates and events (node/level clicks through URL params, mirroring `LogLive.Index`).
- Reuses `LoggerDashboard.Logs.LogRead.list_nodes/0` and `Filter.levels/0`; no DDL change, no new queries.
- Prune confirmation and scope validation (`Prune.parse/1` single-node rule) unchanged.
- Tests: LiveView interaction tests for click-toggles/selects on both pages, prune single-node replacement semantics.

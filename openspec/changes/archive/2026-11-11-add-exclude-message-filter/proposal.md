# Proposal

## Why

Operators can search log messages with wildcards, but there is no way to exclude
rows whose messages match a pattern. Investigating an incident often means
"everything except the noisy health-check lines", which today requires paging
through or exporting and filtering elsewhere.

## What Changes

- Add an `exclude` filter alongside `search`: rows whose `message` matches the
  exclude pattern (same wildcard syntax and term combination as search) are
  removed from the result.
- Apply the exclude predicate on the Logs and Analysis pages, through the same
  shared filter controls and URL params as `search`.
- The Prune page continues to offer no message-based control; `exclude` is
  dropped there just like `search`.
- **BREAKING (result sets)**: a request carrying `exclude` now filters out
  matching rows; existing links without it are unaffected.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `log-viewing`: wildcard message search gains an excluding counterpart.
- `log-analysis`: analysis inherits the exclude predicate.
- `log-filter-controls`: the shared vocabulary gains an exclude control that
  states the same wildcard syntax as search.

## Impact

- `LoggerDashboard.Logs.Filter` — new `exclude` field, parsing, param rendering,
  and `message NOT ILIKE` predicate.
- `LoggerDashboardWeb.LogLive.Index` and `LoggerDashboardWeb.AnalysisLive.Index` —
  new form field and control.
- `LoggerDashboardWeb.FilterControls` — reuse the search control for exclude, or
  add an exclude variant stating the same syntax.
- Raw read path and analysis inherit the new predicate automatically.
- No DDL or upstream change.

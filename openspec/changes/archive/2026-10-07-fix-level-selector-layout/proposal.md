# Proposal

## Why

The level selector on the Logs (`/logs`) and Analysis (`/analysis`) pages overlaps neighbouring filter controls, making the level filter hard to see, hard to click, and visually broken. Fixing the layout restores a usable filter bar on the two most-used dashboard pages.

## What Changes

- Remove the overlapping/duplicate level control: keep a single level selector (toggle badges including `all` reset) as the only level UI on both pages.
- Move the level selector inside the filter card into a well-defined grid row so it cannot overlap node, search, datetime, bucket, or per-page inputs.
- Fix the filter-card grid column spans on both pages so rows wrap cleanly at `md` breakpoints and stack without overlap on narrow screens.
- Preserve all existing filter semantics: comma-separated `level` URL param, toggle-without-disturbing-others, `all`/empty = no predicate, unknown value = validation error, bound parameters.
- No change to log querying, analysis computation, auth, pruning, or retention.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `log-viewing`: level filter presentation/layout on the Logs page — single non-overlapping control inside the filter card.
- `log-analysis`: level filter presentation/layout on the Analysis page — single non-overlapping control inside the filter card, same behaviour as viewer.

## Impact

- Affected code: `LoggerDashboardWeb.LogLive.Index` (template + `form_params`/`join_level_param` if multi-select is removed), `LoggerDashboardWeb.AnalysisLive.Index` (same), shared filter card styling in `app.css` if grid tweaks need CSS.
- Tests: `log_live_test.exs`, `analysis_live_test.exs` (LiveView filter/form assertions); no ClickHouse query changes expected.
- No API, dependency, migration, or config changes.

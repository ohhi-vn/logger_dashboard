# Proposal

## Why

The Logs, Analysis, and Prune pages grew three separate copies of the same filter
controls — node badges, level toggles, a search box, a datetime range, and a
shortcut row — and each copy has drifted: the level row is a multi-select on Logs
and Analysis but a single-select on Prune, the level control sits in different
places on every page, and the same filter intent is expressed three different ways.
That drift is why "clear the errors from the last hour" costs an operator three
different procedures on three different pages.

The same drift shows up in the two features that depend on those filters. The
Analysis page can only draw two charts in one fixed style, and the Prune page —
the one surface where a mistake is irreversible — still asks the operator to
press a button to find out what they are about to delete, then presents the blast
radius as a single line of prose. Search is the third duplicate: the same wildcard
text box is case-sensitive and single-term on all three pages, so an operator who
searches `Timeout` on one page gets different results than `timeout` on another.

## What Changes

- **One shared filter control set.** The node scope badges, level toggle badges,
  and search input move into shared components that the Logs, Analysis, and Prune
  pages all render, configured per page for the differences that are real (multi
  vs. single selection, which page shows a search box). Behavior on every page
  stays what it is today; only the implementation stops being three copies.
- **Case-insensitive, multi-term search.** A search term matches case-insensitively,
  a term with no wildcard matches anywhere in the message, and a search may carry
  several space-separated terms combined with AND. A search whose wildcards wrap
  the whole string stays one phrase. This is a **BREAKING** change to result sets:
  searches that previously matched nothing (differing case, or a bare term that had
  to equal the whole message) now match, and multi-term searches are a new
  capability.
- **Chart styles the Analysis page can choose from.** Each Analysis breakdown
  (by level, volume over time, by node) gets a chart-style control offering the
  types the result's shape supports, with the choice kept in the URL so a shared
  link reproduces the same charts. The by-node breakdown gains a chart beside its
  table, and a requested type that the data cannot support falls back visibly
  rather than rendering an empty canvas.
- **A Prune page that shows its blast radius before it deletes.** The page becomes
  a guided flow: choose the scope, set the cutoff, review, confirm. The review
  step is live — the row count, the per-node split, and a sample of the rows that
  would be deleted update as the scope and filters change — and the explicit
  confirm remains mandatory. The scope, level, cutoff, and confirmation live in
  one card instead of being spread across badges above the form, and the
  confirmation states the resolved instants and the affected nodes rather than a
  prose summary.

## Capabilities

### New Capabilities
- `log-filter-controls`: The shared filter control vocabulary rendered by the Logs,
  Analysis, and Prune pages — node scope options, level toggle options, and the
  search input — including how each page configures selection mode and which
  controls it offers.

### Modified Capabilities
- `log-viewing`: Wildcard text search becomes case-insensitive and accepts multiple
  AND-combined terms; the viewer's filter controls are rendered from the shared
  control set.
- `log-analysis`: Analysis gains a per-breakdown chart-style control and a chart
  for the by-node breakdown; keyword analysis inherits the new search semantics.
- `log-pruning`: The prune page becomes a guided scope → cutoff → review → confirm
  flow whose review step is computed live from the current scope, and whose
  confirmation states the resolved cutoffs and affected nodes.

## Impact

- **Web layer:** `LoggerDashboardWeb.RangeInputs` gains sibling components for the
  node scope, level scope, and search input; `LogLive.Index`,
  `AnalysisLive.Index`, and `PruneLive.Index` render them instead of their own
  copies. The Prune page's markup is restructured around the guided flow, and the
  Analysis page gains chart-style controls.
- **Domain layer:** `LoggerDashboard.Logs.Filter` grows multi-term search parsing
  and case-insensitive predicate emission, affecting `predicates/1` and therefore
  every raw read and every prune. `LoggerDashboard.Logs.Analysis` gains a
  chart-type argument at the call site, and the Prune page's preview path gains a
  per-node count for the review step.
- **Data access:** The message predicate moves from `message LIKE ?` to a
  case-insensitive comparison, still raw SQL with bound parameters — the Ash
  operator limitation recorded in the project context still rules out pushdown.
- **Tests:** LiveView and domain tests for the three pages change with the
  markup and the new search semantics; ClickHouse-backed tests need a running
  ClickHouse instance.

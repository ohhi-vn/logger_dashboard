# Proposal

## Why

Logs, Analysis, and Prune each evolved their own filter UX: a comma-separated node text input duplicated by clickable node badges, plus an explicit Apply/Reset form submit. Operators toggle a node, level, or time shortcut and then must remember to press Apply, while the text input invites typos that the badges already prevent. Log row expansion is single-open (opening one row closes the previous), which slows scanning of related errors. Prune still defaults to single-node scope, adding friction to the common whole-system cleanup.

## What Changes

- **Logs filter redesign:**
  - Remove the comma-separated node text input; keep the distinct-node badge list as the only node selector.
  - Add a `Select all nodes` action to the node badge list (returns to whole-system scope).
  - Remove `Apply filters` and `Reset` form submits; replace with a `Refresh` button plus auto-fetch on every other control (node toggle, level toggle, time preset/picker change, search commit, page-size change).
  - Change row expansion from single-open to multi-open: expanding a row keeps all other expanded rows open.
  - Add `Expand all messages` and `Collapse all messages` shortcut actions for the current page.
- **Analysis filter parity:**
  - Apply the same new Logs filter shape to Analysis (badge-only nodes + select-all, Refresh + auto-fetch, no Apply/Reset, no node text input).
- **Prune filter parity plus prune-specific changes:**
  - Badge-only node selector with no scope select dropdown: clicking a node badge selects single-node scope, Select all in the node list selects whole-system scope.
  - No `Prune all logs` button; an `All time` shortcut in the time list clears both datetime bounds and explicitly permits an unbounded delete of the scope in effect (preview and confirm still required; hand-cleared bounds without it stay rejected).
  - The default prune scope is whole system (`all-nodes`) instead of single-node.
  - **BREAKING (UX & safety):** node text input removal, Apply/Reset removal, single-expand removal, prune scope-select and prune-all-button removal, and the new explicit unbounded prune path alter existing page behavior and controls that relied on them.

## Capabilities

### New Capabilities

- None. This change reworks existing filter and expansion behavior within current capability boundaries.

### Modified Capabilities

- `log-viewing`: node selector shape (badge-only + select-all), filter application model (auto-fetch + Refresh, no Apply/Reset), and row-expansion model (multi-open + expand-all/collapse-all).
- `log-analysis`: same filter-shape and application-model parity with the viewer.
- `log-pruning`: badge-only node selector with no scope select, `All time` shortcut with explicit unbounded prune, and default scope change from single-node to whole-system.

## Impact

- Affected code: `LoggerDashboardWeb.LogLive.Index`, `LoggerDashboardWeb.AnalysisLive.Index`, `LoggerDashboardWeb.PruneLive.Index`, shared `LoggerDashboardWeb.RangeInputs` shortcuts/bound usage, `LoggerDashboard.Logs.Filter` param helpers (only if select-all/prune-all need new param semantics), LiveView tests for all three pages.
- No data-layer or DDL change: predicates stay bound-parameter `Filter.predicates/1` / `Prune.parse/1`; raw-SQL and format invariants unchanged.
- Risk: auto-fetch on every toggle increases query volume; search-as-you-type must be debounced/committed, not per-keystroke, to avoid ClickHouse load. The `All time` shortcut deliberately permits an unbounded prune of the scope in effect, so its preview and confirmation must state the full blast radius (every row in scope, no time bound).

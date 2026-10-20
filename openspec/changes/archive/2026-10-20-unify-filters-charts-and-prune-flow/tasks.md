# Tasks

## 1. Search semantics in the filter domain

- [x] 1.1 Split the `search` param into whitespace-separated terms in `LoggerDashboard.Logs.Filter` (add `search_terms/1` and a per-term wildcard translation, keeping `to_like_pattern/1` for a single term) — verify with `test/logger_dashboard/logs/filter_test.exs` cases asserting that `"*timeout* db_*"` yields two terms, that each term keeps its `*`/`?` translation, and that an empty search yields no terms.
- [x] 1.2 Emit one `message ILIKE ?` clause per term from `Filter.predicates/1`, bound and combined with AND, with no clause for an empty search — verify with a `filter_test.exs` case asserting the clause text, the bound parameter list in term order, and that no user text reaches the SQL string.
- [x] 1.3 Make the keyword paths in `LoggerDashboard.Logs.Analysis` treat any non-empty term list as a keyword scope (`keyword?/1` currently tests the single pattern) — verify with `test/logger_dashboard/logs/analysis_test.exs` coverage that a two-term keyword narrows the level breakdown to rows matching both.
- [x] 1.4 Keep the raw `search` string in `Filter.to_params/1` so the URL and the input keep the operator's typed text — verify with a `filter_test.exs` case asserting the round trip through `parse/1` and `to_params/1` preserves the typed string.
- [x] 1.5 Update the `Filter` moduledoc to state the case-insensitive, multi-term semantics and the `ILIKE` clause — verify by reading the moduledoc against the implemented behavior.

## 2. Scope mutation helpers in the filter domain

- [x] 2.1 Add `toggle_node/2` and `toggle_level/2` (multi-select: add, remove, last removal clears the param) to `LoggerDashboard.Logs.Filter` — verify with `filter_test.exs` cases asserting a toggle adds, a second toggle removes, removing the last member drops the param entirely, and the other params are untouched.
- [x] 2.2 Add `select_node/2` and `select_level/2` (single-select: the clicked value replaces the selection, `all` clears the level) — verify with `filter_test.exs` cases asserting replacement, the `all` reset, and that an unknown level is ignored.
- [x] 2.3 Document the helper vocabulary in the `Filter` moduledoc alongside the existing param helpers — verify the moduledoc names each helper and its mode.

## 3. Shared filter controls component

- [x] 3.1 Create `LoggerDashboardWeb.FilterControls` with a `node_options/1` component rendering the known-node badges plus the select-all and clear actions, parameterized by `mode` (`:multi` / `:single`), the page id prefix, and the selected values — verify with a component test asserting the rendered ids, `aria-pressed` states, and the click target's `phx-value-node`.
- [x] 3.2 Add a `level_options/1` component in the same module with the same two modes, offering the level vocabulary plus the "all levels" reset — verify with a component test asserting the offered options, the active marking in both modes, and the click target's `phx-value-level`.
- [x] 3.3 Add a `search/1` component in the same module that states the syntax it accepts (`*` any run, `?` single character, matching ignores case, space-separated terms combine with AND) and renders the current search value — verify with a component test asserting the syntax text and the rendered input value.
- [x] 3.4 Register `LoggerDashboardWeb.FilterControls` in the `html_helpers` block of `lib/logger_dashboard_web.ex` so the three LiveViews can use it without an alias — verify by compiling with `mix compile --warnings-as-errors`.

## 4. Logs page adopts the shared controls

- [x] 4.1 Replace the Logs page's node badge markup with `FilterControls.node_options/1` in `:multi` mode and its level markup with `FilterControls.level_options/1` in `:multi` mode, keeping one node control and one level control on the page — verify with `test/logger_dashboard_web/live/log_live_test.exs` asserting exactly one node control and one level control are present.
- [x] 4.2 Replace the Logs page's search input with `FilterControls.search/1`, keeping the commit-on-change debounce and the submit path — verify with a `log_live_test.exs` case asserting the search commits on change and that a rejected filter still shows the submitted values beside the error.
- [x] 4.3 Point the Logs page's `toggle-node`, `select-level`, `clear_nodes`, and `select-all-nodes` handlers at the shared `Filter` helpers so the page no longer re-implements the scope logic — verify with a `log_live_test.exs` case asserting that toggling a node and toggling a level both update the URL params and the rendered scope.

## 5. Analysis page adopts the shared controls

- [x] 5.1 Replace the Analysis page's node and level markup with the shared components in `:multi` mode and its search input with `FilterControls.search/1` — verify with `test/logger_dashboard_web/live/analysis_live_test.exs` asserting one node control, one level control, and the shared syntax text on the search control.
- [x] 5.2 Point the Analysis page's scope handlers at the shared `Filter` helpers, leaving the bucket handling as the page's own — verify with an `analysis_live_test.exs` case asserting that toggling a node keeps the bucket and the other filters unchanged.

## 6. Prune page adopts the shared controls

- [x] 6.1 Replace the prune page's node badges with `FilterControls.node_options/1` in `:single` mode, where the selected node names the prune scope — verify with `test/logger_dashboard_web/live/prune_live_test.exs` asserting that clicking a node badge selects the single-node scope and keeps the range and level.
- [x] 6.2 Replace the prune page's level badges with `FilterControls.level_options/1` in `:single` mode and remove the duplicate level select from inside the form, so the page offers exactly one level control — verify with a `prune_live_test.exs` case asserting exactly one level control and that clicking `error` sets the `level` param.
- [x] 6.3 Update the prune page's `select-node` and `select-level` handlers to use the shared `Filter` helpers, keeping the scope param the prune parser expects — verify with a `prune_live_test.exs` case asserting the `scope` and `node` params the request carries.

## 7. Analysis chart styles

- [x] 7.1 Add `level_chart`, `volume_chart`, and `node_chart` params to the Analysis page: accept them in the page's param set, normalize an unknown or absent value to the recommended style, and keep them in the URL — verify with an `analysis_live_test.exs` case asserting an unknown value falls back and the control shows the style in use.
- [x] 7.2 Pass the resolved style to `AshDyan.Charts.to_chartjs/2` for the level and volume breakdowns, and fall back to the recommended style when the result's shape cannot take the chosen one — verify with a test asserting a multi-series volume result asked for a pie style falls back and the control shows the effective style.
- [x] 7.3 Add a chart to the by-node panel beside its table, using the same config-and-hook mechanism — verify with an `analysis_live_test.exs` case asserting the node chart element and its rendered config exist.
- [x] 7.4 Keep the canvas on `phx-update="ignore"` with the config in `data-chart`, and confirm the config is re-rendered when the scope or the style changes — verify with an `analysis_live_test.exs` case asserting the rendered chart config differs after a scope change and after a style change.
- [x] 7.5 Add the chart-style control to each charted panel, changing the style through the URL with no Apply or Run action — verify with an `analysis_live_test.exs` case asserting that picking a style updates the URL param and the rendered chart config.

## 8. Prune live review

- [x] 8.1 Add a bounded per-node count read over the same validated filter, rolling NULL nodes into an explicit `unknown` group — verify with a test in `test/logger_dashboard/logs/log_read_test.exs` (or `prune_test.exs`) asserting the grouped counts and the `unknown` rollup.
- [x] 8.2 Compute the prune review in `handle_params` from the current params — the row count, the per-node counts, and the bounded sample — and remove the separate preview submit and its "Preview prune" button, committing bound edits through the URL with the existing debounce — verify with a `prune_live_test.exs` case asserting the review updates when the level or the cutoff changes and that no delete is dispatched.
- [x] 8.3 Render the review with the resolved UTC cutoffs, an explicit statement for an unbounded scope, the level scope, the per-node counts, and the sample rows, and keep the confirm action acting on the review's parsed filter and scope — verify with a `prune_live_test.exs` case asserting the review names the resolved cutoff and that confirming deletes exactly the reviewed scope.
- [x] 8.4 Clear the review and report the failure when the review read fails, and offer no confirm action in that state — verify with a `prune_live_test.exs` case asserting the error is shown, the review is absent, and no confirm action is offered.
- [x] 8.5 Render the step indicator (scope → cutoff → review → confirm) with the current step marked from the parsed state, without gating the confirm action behind a step advance — verify with a `prune_live_test.exs` case asserting the steps render and the confirm action is reachable without a step-advance action.
- [x] 8.6 Update the prune page's moduledoc and the `Prune` moduledoc to describe the live review, the removed preview action, and the per-node read — verify by reading both against the implemented behavior.

## 9. Integration verification

- [x] 9.1 Run `mix precommit` with a running ClickHouse instance so the `:clickhouse`-tagged tests execute — verify the alias completes without failures and `mix format --check-formatted` reports no diff.
- [x] 9.2 Walk the three pages in a browser to confirm the shared controls behave identically, the chart styles apply and persist in the URL, and the prune review tracks the filters — verify each page loads without console errors, a style choice survives a reload, and the prune review count matches the Logs page's total for the same scope.

## Workflow follow-up

- Archive the change after the project's review requirements are satisfied; the delta specs then update `openspec/specs/log-viewing`, `openspec/specs/log-analysis`, `openspec/specs/log-pruning`, and create `openspec/specs/log-filter-controls`.
- Verify the archived result: the main specs carry the new requirements, and the modified requirements read as one whole block with no lost scenarios.

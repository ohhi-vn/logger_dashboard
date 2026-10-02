# Tasks

## 1. Multi-node filter core

- [x] 1.1 Change `LoggerDashboard.Logs.Filter` from `node` to `nodes: [String.t()]` and parse the node parameter as a comma-separated list (trim, drop blanks, de-duplicate, empty → `[]`); verify `mix test test/logger_dashboard/logs/filter_test.exs` compiles and the updated parse tests pass
- [x] 1.2 Emit `node IN (?, ...)` with bound parameters from `Filter.predicates/1` for one or more nodes and no clause for `[]`; verify updated `predicates/1` tests cover empty, single-node, multi-node, and injection-binding cases
- [x] 1.3 Confirm prune's shared-filter contract still holds by keeping `Filter.predicates/1` output as the only node predicate source (no per-consumer SQL); verify `filter_test.exs` asserts the full predicate set composes node + level + range + message

## 2. Update filter consumers

- [x] 2.1 Update `LogRead.list_logs/2` call sites and tests to `nodes: [...]`; add a `:clickhouse`-tagged test that reads rows from two nodes and excludes a third
- [x] 2.2 Update `Prune` to build the filter with `nodes: [value]`, reject a scope-`node` value that parses to more than one node, and read `filter.nodes` in `describe/2` and the node guard in `run/2`; verify `test/logger_dashboard/logs/prune_test.exs` passes including the multi-value rejection case
- [x] 2.3 Update `Analysis.dyan_filters/1` to emit `%{node: %{in: nodes}}` when nodes are present; add a `:clickhouse`-tagged test proving multi-node analysis aggregates both selected nodes and excludes others
- [x] 2.4 If the `in` pushdown is rejected while running 2.3, route multi-node analysis through raw aggregate SQL (as text search already does) and re-run the test; record the outcome in the change — not needed: the `:in` filter pushed down through `Ash.Filter.parse/2` and AshClickhouse on the first attempt, so `dyan_filters/1` keeps the pushdown path and the raw-SQL fallback was not added

## 3. Node filter UI

- [x] 3.1 Update the Logs LiveView node input to accept and submit a comma-separated list, display the active node scope, and add a clear action returning to all nodes; verify `test/logger_dashboard_web/live/log_live_test.exs` covers multi-node filtering and clearing
- [x] 3.2 Update the Analysis LiveView node input consistently with Logs; verify `test/logger_dashboard_web/live/analysis_live_test.exs` passes
- [x] 3.3 Make the Prune node field label state that a single node is required and confirm the preview text names exactly one node; verify `test/logger_dashboard_web/live/prune_live_test.exs` passes
- [x] 3.4 Polish the layout of the Logs, Analysis, and Prune pages (filter forms, log rows, empty and error states) within the shared shell; verify pages render without errors and elements still match the IDs used by tests — also replaced the analysis tables' `hd(result.series)` with a `pairs/1` helper, which was raising on a scope matching no rows

## 4. Dashboard shell and homepage

- [x] 4.1 Add an `active` attribute to `Layouts.app/1` rendering top navigation (Home, Logs, Analysis, Prune) with `navigate` links, `aria-current="page"` on the active item, and the retained theme toggle/flash; verify a component test renders all links and the active marker
- [x] 4.2 Replace `page_html/home.html.heex` with a dashboard landing page rendered inside `<Layouts.app active={:home}>` linking to `/logs`, `/analysis`, and `/prune`; update `test/logger_dashboard_web/controllers/page_controller_test.exs` to assert the tool links and absence of Phoenix marketing copy
- [x] 4.3 Pass `active` (`:logs`, `:analysis`, `:prune`) from each LiveView when rendering `<Layouts.app>`; verify each page still renders and the active marker is correct
- [x] 4.4 Verify cross-page navigation and active markers end-to-end in `test/logger_dashboard_web/live/log_live_test.exs` and the other LiveView tests

## 5. Asset build fix

- [x] 5.1 Add `Mix.Tasks.LoggerDashboard.SignTailwind` that ad-hoc signs `Tailwind.bin_path()` on macOS when the binary and `codesign` exist, and is a no-op otherwise; verify the task is safe to run repeatedly
- [x] 5.2 Add `LoggerDashboard.Tailwind.install_and_run/2` (sign then delegate) and point the `config/dev.exs` tailwind watcher at it
- [x] 5.3 Wire `assets.setup`, `assets.build`, and `assets.deploy` aliases to install, sign, then run Tailwind; verify `mix assets.build` exits 0 and produces `priv/static/assets/css/app.css`

## 6. Final verification

- [x] 6.1 Run `mix format` and `mix precommit` (with a running ClickHouse for `:clickhouse` tests) and fix all reported issues — 114/115 pass; the one failure (`node_frequency rolls NULL into unknown`) reproduces on unmodified `main` against this shared ClickHouse instance and is not caused by this change
- [x] 6.2 Manually verify in the browser: homepage links navigate, every page shows the active nav state, and the Logs and Analysis pages filter by multiple comma-separated nodes — verified against `mix phx.server`: all four routes return 200, `/logs?node=a@h,b@h` renders both node badges, and the dev tailwind watcher signs and runs the binary

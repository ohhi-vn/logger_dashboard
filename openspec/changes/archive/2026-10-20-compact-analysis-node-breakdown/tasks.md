# Tasks

## 1. Chart style labels

- [x] 1.1 Add `Analysis.chart_style_label/1` to `LoggerDashboard.Logs.Analysis`, mapping every style in `@chart_styles` to a readable name (`bar` → `Bar`, `pie` → `Pie`, `donut` → `Donut`, `line` → `Line`, `area` → `Area`) — verify with a case in `test/logger_dashboard/logs/analysis_test.exs` asserting a label for each style the module offers, and that the style atoms themselves are unchanged.
- [x] 1.2 Render the readable label in the Analysis page's chart-style control while keeping the control's `id` and its `phx-value-style` on the machine name (`pie`, not `Pie`) — verify with a case in `test/logger_dashboard_web/live/analysis_live_test.exs` asserting the button face reads `Pie` and that the control's id is still `analysis-chart-level-style-pie`.
- [x] 1.3 Confirm the style still travels in the URL unchanged when a label is picked — verify with a case in `analysis_live_test.exs` asserting the `level_chart` param still carries the machine name and the chart type still follows it.

## 2. Bounded breakdown charts

- [x] 2.1 Merge `"maintainAspectRatio" => false` into the chart options in `chart_for/2` in `lib/logger_dashboard_web/live/analysis_live/index.ex`, so the option is added in the one place that assembles the config and to all three breakdowns alike — verify with a case in `analysis_live_test.exs` asserting the rendered `data-chart` config for each of the three canvases carries the option.
- [x] 2.2 Move each of the three canvases into a fixed-height wrapper (`relative h-56` with the canvas `block h-full w-full`) so Chart.js measures a definite height instead of deriving one from the column width — verify in a browser that the by-level, by-node and volume charts are the same height at a narrow and at a wide viewport, and that they stay the same height when the scope changes.

## 3. Bounded breakdown result tables

- [x] 3.1 Change the shared `result_table/1` component in `analysis_live/index.ex` to render the table at the shell's compact density (`table-xs`) inside a bounded scrolling region (`max-h-64 overflow-auto`) with a pinned header row (`table-pin-rows`), so all three breakdowns get the same treatment from the one component they already share — verify with a case in `analysis_live_test.exs` asserting `#analysis-levels`, `#analysis-nodes` and `#analysis-volume` all render at the same compact density inside a bounded region.
- [x] 3.2 Confirm a breakdown with more rows than fit still renders every row and scrolls rather than lengthening the page — verify with a case in `test/logger_dashboard_web/live/analysis_live_data_test.exs` seeding enough nodes and buckets to overflow the region, asserting the row count is unchanged and the table is inside the bounded region.

## 4. Breakdown grid

- [x] 4.1 Move the three breakdown cards into one `grid-cols-1 md:grid-cols-6 xl:grid-cols-12` container in `analysis_live/index.ex`, ordered by level, by node, volume over time, with the by-level and by-node cards spanning 3 of 6 at `md` and 3 of 12 at `xl` and the volume-over-time card spanning 6 of 6 at `md` and 6 of 12 at `xl` — verify with a case in `analysis_live_test.exs` asserting the three cards are siblings inside one grid element and that the by-node card carries a column span rather than a full-width one.
- [x] 4.2 Confirm the DOM order matches the visual order so tab order and reading order agree with what is on screen — verify with a case in `analysis_live_test.exs` asserting the rendered order of the three card headings is by level, by node, volume over time.

## 5. Node scope through the shared control

- [x] 5.1 Change `FilterControls.node_options/1` in `lib/logger_dashboard_web/components/filter_controls.ex` to render the union of the `options` it is handed and the `selected` set, with the active scope first and the remaining known options after, deduplicated, and key the "No known nodes." empty text on the rendered union rather than on the known options alone — verify with a case in `test/logger_dashboard_web/components/filter_controls_test.exs` asserting a selected node that is not among the options is rendered first, that a node in both lists is rendered once, and that the empty text does not appear alongside a scope-only node.
- [x] 5.2 Confirm the control's ids, its `aria-pressed` marking and its click events are unchanged by the union — verify with cases in `filter_controls_test.exs` asserting the selected option still carries `aria-pressed="true"` and the same `phx-value-node`, and that an option present in both lists still produces one element with one id.
- [x] 5.3 Remove the Analysis page's duplicate `#analysis-active-nodes` summary row, so the node options are the only statement of the active scope — verify with a case in `analysis_live_test.exs` asserting no such summary element is rendered and that each node in scope is instead offered by `#analysis-node-options` and marked as in scope.
- [x] 5.4 Update the existing `analysis_live_test.exs` cases that address `#analysis-active-nodes` to assert the same facts at the node options instead, covering the empty scope, the single-node scope and the multi-node scope — verify by running the file and confirming the count of passing cases is not reduced.
- [x] 5.5 Confirm the Logs and Prune pages still offer their node options and still scope correctly under the shared control's new option set — verify by running `test/logger_dashboard_web/live/log_live_test.exs` and `test/logger_dashboard_web/live/prune_live_test.exs` with no failures.

## 6. Filter card rows

- [x] 6.1 Move the Bucket select up beside the search input and the range bounds in the Analysis filter card, and rebalance the first row's spans so it fills all six columns (search 3, from 1, to 1, bucket 1), leaving the level options on their own full-width row and the actions on the last row — verify with a case in `analysis_live_test.exs` asserting the bucket select's wrapper carries the same column span as the range bounds' wrappers and that no card row is left partly empty.
- [x] 6.2 Confirm the level options still occupy their own full-width row and the level toggle behaviour is unchanged — verify with a case in `analysis_live_test.exs` asserting the level options sit in a full-width row and that clicking a level still toggles it without disturbing the other filters.

## 7. Limit disclosure

- [x] 7.1 Trim the Analysis page's limit disclosure to the single sentence naming how many rows the results were computed over, dropping the reference to increasing a limit the page does not offer — verify with a case in `analysis_live_test.exs` asserting `#analysis-limit` names the applied bound and no longer names a setting the page does not expose.

## 8. Integration verification

- [x] 8.1 Run `mix precommit` with a running ClickHouse so the `:clickhouse`-tagged tests execute, and confirm the full suite passes with no new warnings and `mix format --check-formatted` reports no diff.
- [x] 8.2 Walk the Analysis page in a browser at a narrow, an intermediate and a wide viewport: confirm the three breakdowns stack, pair and sit side by side as specified, the by-node breakdown never spans the full page, the three charts are the same height at every width, a long result table scrolls inside its region with its header pinned, the node scope is stated once through the node options and can be removed from there, and the chart-style buttons read as names while the URL keeps the machine name.

## Workflow follow-up

- Archive the change after the project's review requirements are satisfied.
- Verify the archived result: the main specs carry the new requirements, and the modified requirements read as one whole block with no lost scenarios.

# Tasks

## 1. Logs page filter layout

- [x] 1.1 Move `#logs-level-options` badge group (with `all` reset) inside `#logs-filter-form` as a full-width `md:col-span-6` row, delete the `multiple` level `<select>`, and set Row 1 spans to node 2 + search 2 + from 1 + to 1 so each row sums to ≤ 6; verify by rendering `/logs` and confirming exactly one level selector exists inside the filter card with no overlap
- [x] 1.2 Simplify `LogLive.Index.form_params/1` to stop mapping `"level"` to a list and remove the `join_level_param/1` list-join branch only if no other field submits a list, keeping `Filter.parse_levels/1` list-tolerant; verify with `mix test test/logger_dashboard/logs/filter_test.exs` and that `?level=error,warning` bookmarks still parse

## 2. Analysis page filter layout

- [x] 2.1 Move `#analysis-level-options` badge group (with `all` reset) inside `#analysis-filter-form` as a full-width `md:col-span-6` row, delete the `multiple` level `<select>`, and set Row 1 to node 2 + search 2 + from 1 + to 1 with bucket + actions on their own trailing row; verify by rendering `/analysis` and confirming exactly one level selector exists inside the filter card with no overlap
- [x] 2.2 Simplify `AnalysisLive.Index.form_params/2` and `allowed_filters/1` the same way as Logs (drop level-as-list mapping, keep parser tolerant); verify with `mix test test/logger_dashboard/logs/filter_test.exs` and that Logs-to-Analysis handoff with `level=error,warning` still applies

## 3. Tests and verification

- [x] 3.1 Update `log_live_test.exs` and `analysis_live_test.exs` assertions from the removed multi-select to the single in-form badge group (presence, `aria-pressed`, toggle patches `level` param, `all` reset, keyboard operability, shared shell styling); verify with `mix test test/logger_dashboard_web/live/log_live_test.exs test/logger_dashboard_web/live/analysis_live_test.exs`
- [x] 3.2 Run `mix precommit` with a running ClickHouse (required for `:clickhouse`-tagged tests) and manually check `/logs` and `/analysis` at 375px, 768px, and 1280px widths for no overlap, correct stacking, and unchanged toggle/filter behaviour; verify precommit passes and visual check shows distinct non-overlapping rows

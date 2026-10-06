# Tasks

## 1. Logs total count

- [x] 1.1 Add `LogRead.count_logs/1` (`SELECT COUNT(*)` with `Filter.predicates/1` bound params, `nil`-rows as error) and verify `mix test test/logger_dashboard/logs/log_read_test.exs` covers matching-filter count, empty-scope zero, and undecodable-format error
- [x] 1.2 Load total alongside page rows in `LogLive.Index` (same parsed `Filter`, cleared on rejected filter/read error) and verify the pagination bar shows `Total N` matching the active filters and zero on empty results
- [x] 1.3 Cover total behavior in LiveView tests (total matches filters, updates on filter change, absent on rejected filter) and verify `mix test test/logger_dashboard_web/live/log_live_test.exs` passes

## 2. Manual prune preview with count and sample

- [x] 2.1 Add bounded prune preview reads (matching-row `COUNT(*)` plus newest-N sample via `Prune.where_clause/1` on the parsed filter, fixed single-digit limit, shared decode path) and verify unit tests cover count, sample order/bound, empty scope, and `nil`-rows error
- [x] 2.2 Render count + sample rows in the `PruneLive.Index` confirmation panel (timestamp, level, node, full message, source location; zero-count states no sample) and verify a previewed scope shows both before confirm is enabled
- [x] 2.3 Keep preview lifecycle safe (cleared on any `handle_params` change and on cancel; `confirm` runs only from stored preview filter/scope) and verify LiveView tests cover param-change clears preview and confirm-without-preview is rejected

## 3. Logs-to-analysis handoff and keyword analysis

- [x] 3.1 Add handoff action on Logs page linking to `/analysis` with active `node`, `search`, `from`, `to`, `level` params and verify clicking it opens Analysis with the same values shown in its filter inputs without changing the Logs page
- [x] 3.2 Add `search` input and param handling to `AnalysisLive.Index` (same wildcard syntax/validation as viewer, preserved across node toggle/level select/bucket change, rejected filter clears results) and verify the form round-trips a keyword through the URL
- [x] 3.3 Implement keyword-aware raw-SQL aggregations (level mix `GROUP BY level`, volume `GROUP BY` time-bucket with ClickHouse date truncation, per-node `GROUP BY node` with NULL/`''` as `unknown`, all sharing `Filter.predicates/1` bound params and shaped to `%AshDyan.Result{}` labels/series) and verify empty-keyword path still uses existing AshDyan calls unchanged
- [x] 3.4 Cover keyword analysis in tests (keyword narrows all three breakdowns, ordering/disclosure hold, empty keyword-scope renders empty tables) and verify `mix test test/logger_dashboard_web/live/analysis_live_test.exs` passes

## 4. Integration verification

- [x] 4.1 Run the full affected suites with a running ClickHouse and verify `mix precommit` passes with no new warnings or failures

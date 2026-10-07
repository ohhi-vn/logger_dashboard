# Tasks

## 1. Shared multi-level filter

- [x] 1.1 Extend `LoggerDashboard.Logs.Filter` to parse `level` as a comma-separated set (or list from a multi-select), normalize `all`/blank/absent to empty, reject unknown levels, round-trip via `to_params`, and emit `level IN (?, ...)` with bound params (empty = no predicate); verify with `mix test test/logger_dashboard/logs/filter_test.exs`
- [x] 1.2 Map the level set in `LoggerDashboard.Logs.Analysis.dyan_filters/1` to omitted when empty and `%{in: levels}` otherwise so pushdown and keyword raw-SQL paths agree; verify with `mix test test/logger_dashboard/logs/analysis_test.exs`

## 2. Logs and Analysis pages

- [x] 2.1 Update `LogLive.Index` `select-level` to toggle (add/remove, `all` clears, empty drops the param), switch badges to `aria-pressed` set membership, make the form level input multi-select, and keep handoff carrying the joined set; verify with `mix test test/logger_dashboard_web/live/log_live_test.exs`
- [x] 2.2 Update `AnalysisLive.Index` identically (toggle handler, badges, multi-select form input, handoff-compatible params); verify with `mix test test/logger_dashboard_web/live/analysis_live_test.exs test/logger_dashboard_web/live/analysis_live_data_test.exs`

## 3. Regression and release check

- [x] 3.1 Update existing single-select level assertions (replace-on-click, form single value) to toggle semantics and add multi-level viewer + analysis coverage (`error,warning` OR match, empty = all, invalid rejected, combines with node/range/search); verify with `mix test test/logger_dashboard/logs/ test/logger_dashboard_web/live/log_live_test.exs test/logger_dashboard_web/live/analysis_live_test.exs`
- [x] 3.2 Run `mix precommit` with ClickHouse running (tests tagged `:clickhouse` need it; DDL via `mix clickhouse_ex_logger.migrate`) and verify it passes with no new warnings

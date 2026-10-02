# Tasks

## 1. Foundation

- [x] 1.1 Add `ash`, `ash_clickhouse`, `ash_dyan`, `clickhouse_ex_logger` deps and verify `mix deps.get && mix compile` succeeds
- [x] 1.2 Configure `ClickhouseExLogger.Repo` in `config/runtime.exs` (env `CLICKHOUSE_URL/USER/PASSWORD/DATABASE`) and supervise it before Endpoint, verify boot reads env and `mix clickhouse_ex_logger.migrate --dry-run` reports planned DDL
- [x] 1.3 Create `LoggerDashboard.Logs` Ash domain plus `LogView` ClickHouse read-model on `logs` with `dyan` whitelist (`level/node frequency`, `timestamp time_bucket`, `allow_filters_on [:node,:level,:timestamp,:message]`, limits) and verify `mix compile` passes DSL verifiers and `AshDyan.Info.analyzable?(LogView)` is true

## 2. Log viewing

- [x] 2.1 Implement filter builder (node equality/all-nodes, `*`/`?` wildcard to `LIKE` with escaping, UTC datetime-range validation rejecting `from > to`, level `error/warning/info/debug/all`) and verify unit tests cover wildcard translation, range rejection, and predicate composition
- [x] 2.2 Build `LogLive.Index` with `Layouts.app`, `<.input>` filters, `stream/3` + `phx-update="stream"`, `timestamp desc` sort, limit/offset pagination preserving filters, and add `/logs` route, verify LiveView tests assert `has_element?` for `#logs-filter-form`, `#logs-list`, pagination and empty state
- [x] 2.3 Handle missing/unmigrated `logs` table (including legacy tables without `node`) with friendly "run migrate" state instead of 500 and verify test simulates `ConfigurationError`/missing-table path

## 3. Log analysis

- [x] 3.1 Implement server-side analysis presets via `AshDyan.run/2` (level frequency, volume `time_bucket` hour/day with optional level split, node frequency with `unknown` for NULL) reusing viewer scope filters and verify `AshDyan.run` returns expected `labels/series` on seeded ClickHouse rows
- [x] 3.2 Build `AnalysisLive.Index` (`/analysis`) with scope + time-range + bucket controls, Chart.js rendering via `app.js` import of `AshDyan.Charts.to_chartjs/1` shape (no inline `<script>`), limit-disclosure badge, and `unknown` node row, verify LiveView tests assert charts/tables render and limit badge appears
- [x] 3.3 Enforce `max_group_by`/`max_limit`/`timeout` on every analysis request and verify tests assert over-limit requests are capped and disclosed rather than silently truncated

## 4. Log pruning

- [x] 4.1 Implement prune destroy path (`Ash.bulk_destroy`/`destroy_query` with resolved node/time/level filter compiling to `ALTER TABLE ... DELETE`) and verify ClickHouse-backed test deletes only scoped rows
- [x] 4.2 Build prune UI with scope picker (`node` + input vs `all-nodes`), shared time/level filters, two-step confirmation showing resolved predicate, POST-only LiveView event (no GET delete), success/failure reporting noting async-apply semantics, and verify LiveView tests cover confirm, cancel-deletes-zero, missing-node rejection, and failure message

## 5. Release verification

- [x] 5.1 Add/refresh README + release notes (migrate-before-boot, `bin/app eval "ClickhouseExLogger.Utils.migrate()"`, async-delete + no-auth warnings) and verify docs list exact commands
- [x] 5.2 Run `mix precommit` and fix warnings/format/test failures, verify command passes clean

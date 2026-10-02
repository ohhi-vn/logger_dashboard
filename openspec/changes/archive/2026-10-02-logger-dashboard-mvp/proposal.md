# Proposal

## Why

Elixir clusters using `clickhouse_ex_logger` ship logs to ClickHouse but have no purpose-built UI to read them. Operators currently need raw SQL (`SELECT ... FROM logs`) to answer "what failed on node X?" This change provides the initial LoggerDashboard MVP so logs stored via `clickhouse_ex_logger` become viewable, filterable, analyzable, and prunable from Phoenix.

## What Changes

- Add `ash`, `ash_clickhouse`, `ash_dyan`, and `clickhouse_ex_logger` dependencies and configure a read/query path against the existing `logs` table (`ORDER BY timestamp`, `node`, `level`, `message`, `timestamp` columns).
- Add log viewer LiveView: list logs for a selected node (or all nodes) with pagination/sorting, default newest-first.
- Add log filtering: wildcard text search on `message`, datetime range on `timestamp`, level filter (`error`, `warning`, `info`, `debug`, plus all), node scope filter.
- Add analysis page: system-wide or per-node charts/tables powered by `AshDyan.run/2` (frequency by level, time-bucketed volume, per-node breakdown) with matching scope + time-range filters.
- Add prune control: delete logs for a single node or whole system by time-range/level scope with explicit confirmation and result counts.
- Add `mix clickhouse_ex_logger.migrate`-compatible startup check/docs so dashboard never queries before `logs` table (including `node` column) exists.

## Capabilities

### New Capabilities

- `log-viewing`: browse paginated logs scoped by node/all-nodes with text-wildcard, datetime-range, level, and node filters.
- `log-analysis`: system-wide or per-node log analytics (level frequency, volume over time, per-node breakdown) via AshDyan with shared filter scope.
- `log-pruning`: prune logs for one node or the whole system by explicit scope with confirmation and auditable outcome.

### Modified Capabilities

- None — greenfield dashboard on a fresh Phoenix app; no existing specs.

## Impact

- Dependencies: `ash`, `ash_clickhouse`, `ash_dyan`, `clickhouse_ex_logger`, `clickhouse` client; ClickHouse connection config in `runtime.exs`; `ClickhouseExLogger.Repo` (or dashboard-owned AshClickhouse repo reusing same table) added to supervision tree.
- Code: new Ash domain/resources (read-only `LogEntry` view + prune actions), new LiveViews (`LogLive.Index`, `AnalysisLive.Index`, prune UI), router additions, AshDyan `dyan` whitelist.
- Systems: read-heavy ClickHouse queries (time-pruned via `ORDER BY timestamp`); prune uses `ALTER TABLE ... DELETE` semantics (async, non-transactional); no change to log ingestion path.

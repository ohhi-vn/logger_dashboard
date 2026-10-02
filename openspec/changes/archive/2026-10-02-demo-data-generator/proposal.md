# Proposal

## Why

Local dev and demo environments start with an empty `logs` ClickHouse table, so `/logs`, `/analysis`, and `/prune` show empty states and cannot be exercised without manually shipping real logs.

## What Changes

- Add a dev/demo Mix task `mix logger_dashboard.seed_logs` that writes synthetic rows directly to the shared `logs` table via `ClickhouseExLogger.LogEntry` create.
- Support multiple log levels (`debug`, `info`, `warning`, `error`) with realistic per-level message templates plus caller attrs (`module`, `function`, `file`, `line`) and stringified `metadata`.
- Support multiple nodes via `--nodes` list (e.g. `web@10.0.0.1,worker@10.0.0.2`) with per-row node assignment (`--node-distribution random|round-robin|weighted`) and NULL-node rows omitted by default.
- Support date-range spread via `--from` / `--to` ISO8601 UTC bounds with random or sequential timestamp distribution across the range; default to last 7 days.
- Support volume/scale controls: `--count`, `--batch-size`, `--seed` for reproducible runs, plus `--preset small|medium|burst` for common demo sizes.
- Make generation idempotent-safe and non-destructive: only inserts, never deletes; `--dry-run` prints planned counts without writing; task refuses to run in `prod` unless `--allow-prod` is passed.

## Capabilities

### New Capabilities

- `demo-data`: synthetic log generation for dev/demo covering levels, nodes, date-range, volume, reproducibility, and safety guards.

### Modified Capabilities

- None — existing `log-viewing`, `log-analysis`, `log-pruning` REQUIREMENTS are unchanged; the generator only produces rows they already handle.

## Impact

- New code: Mix task + generator module under `lib/logger_dashboard/dev/` (or `lib/mix/tasks/`), no changes to `LogView`, `Filter`, LiveViews, or pruning logic.
- Dependencies: none new — reuses `ash`, `ash_clickhouse`, and `clickhouse_ex_logger` already in `mix.exs`.
- Systems: writes to ClickHouse `logs` table in `dev`/`test` (opt-in in `prod`); documented as dev tooling, not part of the release runtime path.

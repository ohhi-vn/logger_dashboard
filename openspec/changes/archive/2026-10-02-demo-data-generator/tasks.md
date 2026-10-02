# Tasks

## 1. Pure generator core

- [x] 1.1 Create `LoggerDashboard.Dev.Seeder` with options struct, validation (levels/nodes/range/count), and seeded `:rand` generation, verified by `mix compile` succeeding with no warnings
- [x] 1.2 Implement per-level message + caller + metadata catalogs emitting `Event.row`-shaped maps, verified by unit test asserting all four levels produce populated `message/module/function/file/line/metadata`
- [x] 1.3 Implement node assignment (`round-robin`/`random`) and timestamp spread (`random-uniform`/`even`, default last 7 days), verified by unit tests for multi-node cycling, in-range timestamps, and invalid range rejection

## 2. Mix task CLI and write path

- [x] 2.1 Create `mix logger_dashboard.seed_logs` with `OptionParser` flags, presets, `--seed`, `--batch-size`, and `--dry-run` planning output, verified by `mix logger_dashboard.seed_logs --help` printing documented flags
- [x] 2.2 Wire chunked writes through `ClickhouseExLogger.Insert.insert/1` with per-batch progress and summary counts, verified by seeded run inserting exact `--count` rows visible in `/logs`
- [x] 2.3 Add safety guards (insert-only, prod requires `--allow-prod`, invalid levels/range abort with no writes), verified by unit/integration tests for dry-run zero-write and prod-guard abort

## 3. Verification and docs

- [x] 3.1 Add `Seeder` unit tests for level mix, node distribution, timestamp bounds, and seed repeatability (excluding `id`), verified by `mix test test/logger_dashboard/dev/seeder_test.exs` passing
- [x] 3.2 Add task-level test with ClickHouse (or tagged integration) covering small preset end-to-end and dry-run, verified by `mix test --include integration` passing locally against ClickHouse
- [x] 3.3 Document usage in `README.md` (presets, examples for multi-node/date-range, prune cleanup note) and verify with `mix precommit` passing

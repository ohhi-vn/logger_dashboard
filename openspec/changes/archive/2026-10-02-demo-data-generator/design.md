# Design

## Context

See proposal.md Why. Current state: empty `logs` ClickHouse table in dev/demo; `LogView` (`lib/logger_dashboard/logs/log_view.ex`) is a read-model over that table with `migrate false`; DDL owned upstream by `clickhouse_ex_logger`. No existing seed path — `priv/repo/seeds.exs` is the Phoenix-postgres stub. `ClickhouseExLogger.Insert.insert/1` is the proven batch write path (chunks at 1000, uses data-layer encoding); `Ash.bulk_create/4` is broken on `ash_clickhouse 0.7.3` (leaks internal opts, datetime overflow — see `Insert` moduledoc).

## Goals / Non-Goals

**Goals:**
- One Mix task that fills `/logs` + `/analysis` + `/prune` demo flows with believable multi-level, multi-node, date-ranged data.
- Deterministic re-runs and safe defaults for dev/demo.

**Non-Goals:**
- No UI for generation; no changes to viewer/analysis/prune behavior.
- No auth, no Postgres seeding, no production log pipeline changes.
- No new Hex deps; no DDL/migration changes.

## Decisions

1. **Write via `ClickhouseExLogger.Insert.insert/1` with `Event.row`-shaped maps (not `Ash.bulk_create`, not live `Logger`).**
   - Rationale: `Insert` is the only verified bulk path on installed versions; it reuses table/column/encoding from `LogEntry` and handles timestamps + chunking + partial-success counts. Going through the live `Logger` handler would be async/lossy and depend on handler install state.
   - Alternative considered: `Ash.bulk_create` on `LogView`/`LogEntry` — rejected per `Insert` moduledoc defects. Alternative: raw `ClickHouse.insert_rows` SQL — rejected, duplicates encoding logic.

2. **Split pure builder vs thin Mix task: `LoggerDashboard.Dev.Seeder` + `mix logger_dashboard.seed_logs`.**
   - Rationale: builder is pure (`seed -> [row]`) and unit-testable without ClickHouse; task only parses CLI (`OptionParser`), seeds `:rand`, chunks, calls `Insert`, prints summary. Matches Phoenix `lib/mix/tasks/` convention; no existing tasks to conflict with.
   - Row shape follows `ClickhouseExLogger.Event.row` type: `id` via `Ash.UUID.generate()`, `level` as atom, `timestamp` as `DateTime` UTC, `metadata` stringified with `term:` marker convention for compounds.

3. **CLI surface with `OptionParser`: `--count --levels --nodes --node-distribution --from --to --time-distribution --batch-size --seed --preset --dry-run --allow-prod`.**
   - Rationale: covers spec (levels/nodes/range/volume/repro/safety) with one parser; presets (`small ~500`, `medium ~5k`, `burst ~20k spiky`) just fill defaults before explicit flags win.
   - Level mix default weighted (e.g. info-heavy, error-rare) so analysis charts look real; `--levels` subset renormalizes weights.
   - Node assignment `round-robin | random`; timestamps `random-uniform | even` across `[from,to]`, default last 7 days.
   - Message catalog: per-level templates with interpolations (timeouts, db pool, request ids, node names) + matching `module/function/file/line` pools so rows join plausibly with filters.

4. **Reproducibility via `:rand.seed(:exsss, ...)`.**
   - Rationale: single seeded algorithm for level/node/time/template picks makes `--seed` reruns byte-identical in sequence; `Ash.UUID.generate()` is random per row but excluded from determinism contract (ids only need uniqueness).

5. **Safety in task, not builder: `Mix.env() == :prod` requires `--allow-prod`; `--dry-run` builds first N sample rows and prints plan without calling `Insert`.**
   - Rationale: keeps builder side-effect free; guard is one `if` at task entry, easy to audit.

## Risks / Trade-offs

- [ClickHouse async-insert visibility delay] → Mitigation: `Insert` already sets `wait_for_async_insert: 1`; task prints row counts and advises re-query after seconds for large bursts.
- [Large `--count` timeouts/memory] → Mitigation: stream-generate in `--batch-size` chunks (default 1000, matching `Insert` chunk), never materialize full list; document `burst` as opt-in.
- [`level` atom vs ClickHouse string drift] → Mitigation: emit atoms (`:error` etc.) exactly as `Event.row` does; let data-layer encoding handle storage; round-trip verified by existing `Filter.maybe_filter_level`.
- [Seed determinism vs UUID randomness] → Mitigation: contract covers field sequence, not `id` values; document explicitly.
- [Dev-only code in release artifact] → Mitigation: task + builder are dev tooling; task aborts in prod without flag and is excluded from release docs path.

## Migration Plan

- Additive only: new files, no migrations, no config changes.
- Deploy: `mix deps.get` (no new deps) → `mix clickhouse_ex_logger.migrate` already done → `mix logger_dashboard.seed_logs --preset small --dry-run` → real run → verify `/logs` + `/analysis`.
- Rollback: delete generated rows via existing `/prune` flow or `ALTER TABLE logs DELETE`; no code rollback needed beyond reverting new files.

## Open Questions

- None blocking. Preset sizes and default level weights can be tuned after first demo without spec change.

# Design

## Context

See `proposal.md` Why for motivation. Current state (observed):

- Fresh Phoenix 1.8 + LiveView 1.2 app (`LoggerDashboardWeb.Router` only has `/`; `LoggerDashboard.Application` supervises `Repo` (Postgres), PubSub, Telemetry, Endpoint).
- No `ash`, `ash_clickhouse`, `ash_dyan`, or `clickhouse_ex_logger` in `mix.exs`; no `openspec/specs/*` yet.
- Upstream contract (from HexDocs): `clickhouse_ex_logger` owns `logs` table (`id UUID`, `timestamp DateTime64(6)` UTC, `level String`, `message String`, `module/file/function/line/metadata`, `node Nullable(String)`), `ENGINE=MergeTree() ORDER BY (timestamp)`, plus `ClickhouseExLogger.Repo`, `ClickhouseExLogger.LogEntry` (Ash resource), `ClickhouseExLogger.Handler/Buffer`, and `mix clickhouse_ex_logger.migrate` (creates DB + `logs`, incl. `node` column; safe re-run).
- `AshClickhouse` v0.7.x supports filter/sort/limit/offset/select, `destroy_query` via `ALTER TABLE ... DELETE`, no transactions/locks/keyset/joins. `AshDyan` v0.6 runs `AshDyan.run(spec)` through the resource read action and aggregates in memory bounded by `max_limit`; `dyan` DSL is the whitelist.

## Goals / Non-Goals

**Goals:**

- Reuse upstream `logs` table + encoding as single source of truth; dashboard adds only read/filter/analyze/prune UX.
- Time-pruned ClickHouse reads (always bound time range or limit) and stream-based LiveView lists.
- Runtime analytics without per-chart actions via AshDyan whitelist.

**Non-Goals:**

- No change to ingestion (`Handler`/`Buffer`/`Insert` workaround stays upstream).
- No auth/roles in MVP (open dashboard); no retention automation/cron — only manual prune action.
- No raw-SQL query console; no per-message full-text index in MVP.

## Decisions

### 1. Reuse `ClickhouseExLogger.Repo` + `LogEntry` for reads; dashboard owns only UI domain

- What: Add `ClickhouseExLogger.Repo` to supervision tree; read via `ClickhouseExLogger.LogEntry` with `Ash.Query`. Dashboard defines `LoggerDashboard.Logs` Ash domain for code interfaces (`list_logs`, `prune_logs`, `analyze`) rather than redefining the table.
- Why: Avoids dual DDL/encoding drift (upstream `Insert` workaround for `bulk_create` + `DateTime64`, `node` column upgrade). `mix clickhouse_ex_logger.migrate` remains the migrator.
- Alternative (dashboard-owned duplicate resource on same table): rejected — two writers of table DSL diverge; upgrades (e.g. new columns) missed.
- Analysis exception: `LogEntry` lives in the dep and cannot carry `extensions: [AshDyan]`. Dashboard defines a thin read-model `LoggerDashboard.Logs.LogView` (same `table "logs"`, same `repo ClickhouseExLogger.Repo`, `data_layer AshClickhouse.DataLayer`) with `extensions: [AshDyan]` + `dyan` whitelist (`level:frequency`, `timestamp:time_bucket [:minute,:hour,:day,:week,:month]`, `node:frequency`, `allow_filters_on [:node,:level,:timestamp,:message]`, `max_group_by 2`, `max_limit 10_000`). Reads and analysis share the same table; writes/prune go through `LogEntry`/`LogView` destroy path.

### 2. Filters map to Ash filters (ClickHouse-pushable)

- `node`: `node == ^node` or no predicate for all-nodes (NULL rows appear only in all-nodes).
- `level`: equality; `all` = no predicate.
- `timestamp`: `timestamp >= ^from and timestamp <= ^to`; require parseable UTC datetimes, reject `from > to` without querying.
- `message` wildcard: translate user `*` → `%`, `?` → `_`, escape existing `%_\\`, emit `like(message, pattern)` (case-sensitive MVP). Empty = no predicate.
- Sort `timestamp: :desc`, `limit`/`offset` pagination (keyset unsupported). LiveView uses `stream/3` + `phx-update="stream"` per LiveView guidelines.

### 3. Analysis is a thin LiveView adapter over `AshDyan.run/2`

- Presets only (no free-form spec builder in MVP): `level frequency`, `volume time_bucket` (bucket hour/day, split by level optional), `node frequency` (system scope). Spec built server-side from same scope filters; `group_by` ≤ `max_group_by`; `limit` = `max_limit` with disclosure badge.
- Render `AshDyan.Result{labels, series}` via `AshDyan.Charts.to_chartjs/1` to Chart.js (imported in `app.js`, no inline `<script>`, colocated hook only if canvas lifecycle needs it).
- Why presets: keeps `dyan` whitelist small and avoids exposing arbitrary column/function pickers before auth exists.

### 4. Prune via Ash destroy with confirmation + POST-only

- UI: scope picker (`node` + text input vs `all-nodes`), same time/level filters, two-step confirm showing resolved predicate. LiveView `handle_event("prune")` only; no GET route deletes.
- Execution: `Ash.bulk_destroy` / `destroy_query` on the dashboard resource with the resolved filter (compiles to `ALTER TABLE logs DELETE WHERE ...`). Report `{:ok, count}` or "mutation dispatched — ClickHouse applies asynchronously; rows disappear after mutation completes". Failure surfaces ClickHouse error + scope.
- Alternative raw `ALTER TABLE ... DELETE`: rejected — bypasses Ash validation/actor plumbing and duplicates table config.

### 5. Config and boot order

- `config/runtime.exs`: `config :clickhouse_ex_logger, ClickhouseExLogger.Repo, url/username/password/database` from env (`CLICKHOUSE_URL` etc.). Children order: `ClickhouseExLogger.Repo` before Endpoint. README + release checklist: run `mix clickhouse_ex_logger.migrate` (or `bin/app eval "ClickhouseExLogger.Utils.migrate()"`) before boot; dashboard shows friendly "logs table missing — run migrate" state on `ConfigurationError`/missing-table instead of 500.

## Risks / Trade-offs

- [ClickHouse deletes are async + heavy, no transactions] → Mitigation: confirmation gate, default to time-bounded prune, warn that large deletes mutate in background; no auto-retention in MVP.
- [AshDyan aggregates in memory bounded by `max_limit`] → Mitigation: disclose applied limit on every chart; presets choose narrow columns only; never claim full-dataset exactness past the cap.
- [Wildcard `LIKE %...%` over `message` full-scans parts] → Mitigation: always combine with time range + limit; document that message index (`ngrambf/tokenbf`) is future work, not MVP.
- [Old `logs` tables lack `node` column → whole batch rejected upstream, dashboard reads fail] → Mitigation: startup/docs force re-run of upstream migrate; dashboard error state names the fix.
- [No auth in MVP] → Mitigation: prune is destructive; document as known gap, recommend `Plug.BasicAuth`/network isolation until auth change; keep prune behind explicit confirm + POST.
- [Upstream `bulk_create` workaround irrelevant to reads but version-pinned `ash_clickhouse ~> 0.7`] → Mitigation: pin same minor in dashboard; `mix precommit` + ClickHouse-backed tests via testcontainers pattern from upstream.

## Migration Plan

1. Add deps (`ash`, `ash_clickhouse`, `ash_dyan`, `clickhouse_ex_logger`), `mix deps.get`, configure `runtime.exs`, add `ClickhouseExLogger.Repo` to supervision tree.
2. Run `mix clickhouse_ex_logger.migrate` (dev/test container; prod via release eval) to ensure `logs` + `node` column.
3. Add domain/resources (`Logs` domain, `LogView` with `dyan`), LiveViews (`LogLive.Index`, `AnalysisLive.Index`, prune component), router entries, Chart.js import.
4. Deploy: migrate first, then release; rollback = revert release (ClickHouse `DELETE` mutations are not rolled back — document).
5. Verify: `mix precommit`; LiveView tests with `has_element?` on filter/pagination/confirm IDs; ClickHouse-backed tests gated on container availability per upstream pattern.

## Open Questions

- None blocking specs/approach/tasks. Deferred: auth model for prune/analysis, default retention windows, message full-text index choice.

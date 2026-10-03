# Proposal

## Why

The dashboard reads only ClickHouse (`ClickhouseExLogger.Repo`); `LoggerDashboard.Repo` (Postgres) is never queried and `priv/repo/migrations` is empty, yet prod boot hard-requires `DATABASE_URL`, every developer/test bootstrap pulls Postgres (`mix ecto.setup`, sandbox, `CheckRepoStatus`), and the README documents Postgres as required. Operators must supply a database the system never uses, and there is no declarative way to run the real stack (dashboard + ClickHouse).

## What Changes

- Add `compose.yaml` at repo root defining the full stack — dashboard (built from existing `Containerfile`) + single-node ClickHouse (`clickhouse/clickhouse-server:26.9`) — runnable via `podman compose up --build` (docker-compatible).
- Apply ClickHouse DDL (`/app/bin/migrate`) as part of dashboard container start, gated on ClickHouse authenticated readiness; persist ClickHouse in a named volume; publish ClickHouse ports on loopback only.
- Provision stack secrets via gitignored `.env` + committed `.env.example` with fail-fast `${VAR:?...}` interpolation for `SECRET_KEY_BASE`, `CLICKHOUSE_PASSWORD`, `DASHBOARD_AUTH_TOKEN`.
- **BREAKING** Remove Postgres scaffolding entirely: delete `LoggerDashboard.Repo`, `Ecto.Adapters.Postgres` config (`config/dev.exs`, `config/test.exs`, `config/runtime.exs` prod block, `config/config.exs` `ecto_repos`), `postgrex`/`ecto_sql`/`phoenix_ecto` deps, `ecto.setup`/`ecto.reset` aliases and `test` alias `ecto.*` prefix, `test/support/data_case.ex` sandbox + `test/test_helper.exs` sandbox mode, `Phoenix.Ecto.CheckRepoStatus` plug, `priv/repo/` directory, and all `DATABASE_URL`/`POOL_SIZE`/`ECTO_IPV6` documentation.
- Update `README.md`: podman-compose lifecycle (prereqs, `.env` generation, up/down/logs, volume-reset semantics), container `podman run` examples without `DATABASE_URL`, configuration table without Postgres rows, and plain-HTTP/TLS caveat.
- Update `.gitignore` (ignore `.env`) and `.formatter.exs` (`import_deps` without `ecto_sql`).

## Capabilities

### New Capabilities

- `compose-deployment`: single-node Podman Compose stack for the dashboard — dashboard + ClickHouse service definitions, persistent ClickHouse storage, credential provisioning, DDL bootstrap ordering, and the documented operator lifecycle.

### Modified Capabilities

- `container-image`: the "Runtime configuration via environment" requirement changes — `DATABASE_URL`, `POOL_SIZE` (and `ECTO_IPV6`) are removed; the release configures only `PHX_HOST`, `PORT`, `SECRET_KEY_BASE`, `CLICKHOUSE_*`, `DASHBOARD_AUTH_TOKEN`, boots with no Postgres repo, and fail-fast covers `SECRET_KEY_BASE` only.

## Impact

- **New files**: `compose.yaml`, `.env.example`.
- **Deleted**: `lib/logger_dashboard/repo.ex`, `priv/repo/` (`migrations/.formatter.exs`, `seeds.exs`), `test/support/data_case.ex` (or stripped of Ecto sandbox if file must remain for helpers — see design).
- **App boot/config**: `lib/logger_dashboard/application.ex` (drop `LoggerDashboard.Repo` child), `config/config.exs` (drop `ecto_repos`), `config/dev.exs`, `config/test.exs`, `config/runtime.exs` (drop Postgres blocks), `lib/logger_dashboard_web/endpoint.ex` (drop `CheckRepoStatus`), `mix.exs` (drop 3 deps + ecto aliases), `mix.lock`, `.formatter.exs`, `test/test_helper.exs`.
- **Docs/metadata**: `README.md` (deployment section, config table, container examples), `.gitignore` (`.env`).
- **Unchanged**: `Containerfile`, `.containerignore`, `rel/overlays/bin/*`, all ClickHouse query paths, every route, and the token gate. No new dependency.
- **Operators**: existing prod deployments setting `DATABASE_URL` must drop it (ignored/removed, no longer read); no data migration (Postgres held no dashboard data). Relationship to in-flight `add-compose-deployment`: this change subsumes its interim optional-Postgres step and completes the removal its Non-goals deferred; only one of the two `container-image` deltas should land.

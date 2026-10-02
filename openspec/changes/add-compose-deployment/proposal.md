# Proposal

## Why

Today the only supported way to run the dashboard is a manual sequence an operator has to assemble themselves: build the image, start a ClickHouse container, publish `8123`, apply the ClickHouse DDL with a throwaway container, then start the dashboard with seven environment variables copied from the README. Nothing in the repository encodes the wiring, so the ordering, the credentials, and the schema bootstrap are all tribal knowledge and every new deployment repeats them.

Separately, prod boot still hard-requires `DATABASE_URL` and supervises `LoggerDashboard.Repo` even though the dashboard reads only ClickHouse (`priv/repo/migrations` is empty and no code queries the repo). That vestigial requirement is the only thing standing between the current code and a two-service deployment: without it, the dashboard cannot start alongside ClickHouse alone.

## What Changes

- Add a `compose.yaml` at the repository root defining the full stack — the dashboard and a single-node ClickHouse — buildable from the existing `Containerfile` with `podman compose up --build`.
- Apply the ClickHouse DDL (`/app/bin/migrate`, wrapping `ClickhouseExLogger.Utils.migrate/0`) as part of the dashboard container's start command so the service never serves traffic before the `logs` table exists; ClickHouse readiness is gated by a healthcheck plus `depends_on: condition: service_healthy`.
- Persist ClickHouse in a named volume and publish its ports on loopback only, keeping the store and its credentials off the network.
- Provision secrets through a gitignored `.env` with a committed `.env.example`; required variables use `${VAR:?...}` interpolation so a missing secret fails at `podman compose config`/`up` time instead of at boot.
- Make the Postgres repo optional: `config/runtime.exs` configures `LoggerDashboard.Repo` only when `DATABASE_URL` is present, and `LoggerDashboard.Application` supervises it only when configured. `DATABASE_URL` stops being a required prod secret. This is a **BREAKING** change to the documented prod boot contract (`DATABASE_URL` no longer raises when absent).
- Declare the dashboard healthcheck in `compose.yaml` rather than relying on image metadata, since podman drops the `HEALTHCHECK` instruction unless the image is built with `--format docker`.
- Document the stack in `README.md`: prerequisites, `.env` generation (`mix phx.gen.secret`, `mix logger_dashboard.gen.token`), up/down/logs commands, volume-reset semantics, and the plain-HTTP/TLS caveat of the prod `force_ssl` setting.

## Capabilities

### New Capabilities

- `compose-deployment`: single-node Podman Compose stack for the dashboard — dashboard + ClickHouse service definitions, persistent ClickHouse storage, credential provisioning, DDL bootstrap ordering, and the documented operator lifecycle.

### Modified Capabilities

- `container-image`: the "Runtime configuration via environment" requirement changes — `DATABASE_URL` becomes optional and the release boots against ClickHouse alone, so the fail-fast scenario now covers `SECRET_KEY_BASE` only.

## Impact

- **New files**: `compose.yaml`, `.env.example`.
- **App boot**: `lib/logger_dashboard/application.ex` (conditional repo child), `config/runtime.exs` (conditional repo config, no `DATABASE_URL` raise).
- **Docs/metadata**: `README.md` (deployment section, configuration table), `.gitignore` (ignore `.env`).
- **Unchanged**: `Containerfile`, `.containerignore`, `rel/overlays/bin/*`, all ClickHouse query paths, every route, and the token gate. No dependency added or removed; the dev/test Postgres scaffolding stays as-is (see Non-goals).
- **Operators**: existing prod deployments that set `DATABASE_URL` are unaffected — the repo is still configured and supervised when the variable is present. Deployments that omitted it previously crashed at boot; they now start.

## Non-goals

- Removing the Postgres scaffolding itself (the `postgrex`/`ecto_sql`/`phoenix_ecto` deps, `mix ecto.*` aliases, `test/support/data_case.ex`, and `test/test_helper.exs` sandbox mode). This change only stops prod boot from depending on it; the full removal touches the dev/test workflow and deserves its own change.
- Clustered or replicated ClickHouse, ClickHouse tuning beyond the single-node defaults, TLS certificates, or a reverse proxy in front of the dashboard.
- Seeding demo data inside the stack, and CI that runs `podman compose`.
# Design

## Context

Current state that shapes the approach:

- `Containerfile` builds a runnable release image whose `CMD` is `/app/bin/logger_dashboard start`, whose runtime user is `nobody`, and whose `HEALTHCHECK` probes `http://localhost:4000/logs` accepting `200` or `401` (every route is behind the token gate).
- `rel/overlays/bin/server` is `PHX_SERVER=true exec ./logger_dashboard start` and `rel/overlays/bin/migrate` is `logger_dashboard eval "ClickhouseExLogger.Utils.migrate()"`. The release script's own help text describes `eval` as executing "on a new, non-booted system", and `ClickhouseExLogger.Utils.migrate/0` starts and stops its own `ClickhouseExLogger.Repo` connection. So the DDL step needs `CLICKHOUSE_*` configuration and `SECRET_KEY_BASE` (evaluated in `config/runtime.exs` at release boot) but no running supervision tree and no `DATABASE_URL`.
- `config/runtime.exs` raises in prod when `DATABASE_URL` is missing, and `LoggerDashboard.Application` supervises `LoggerDashboard.Repo` unconditionally, so today the release cannot boot without a reachable Postgres even though nothing reads it.
- The ClickHouse image used in the README is `clickhouse/clickhouse-server:26.9`.
- Podman only records the `HEALTHCHECK` instruction when the image is built with `--format docker`, and Podman Compose may build with the default OCI format.

See `proposal.md` for motivation and `specs/` for the behavior contract.

## Goals / Non-Goals

**Goals:**

- Two services, two files of new configuration (`.env.example`, `compose.yaml`), one command to a working stack.
- No new application surface: reuses the existing `Containerfile`, the two release overlay scripts, and the existing env-var configuration contract.
- Deterministic credentials — no secret rotates behind the operator's back after a restart.

**Non-Goals:**

- Removing the Postgres scaffolding from `mix.exs`, test helpers, and aliases (see proposal Non-goals). This change only makes prod boot independent of it.
- Tuning ClickHouse beyond single-node defaults, TLS/proxying, backup strategy, or seeding demo data in the stack.

## Decisions

### DDL runs inside the dashboard container, not as a third one-shot service

The dashboard service starts with `command: ["/bin/sh", "-c", "/app/bin/migrate && exec /app/bin/server"]`, gated by `depends_on: clickhouse: {condition: service_healthy}`.

Rationale: the canonical compose pattern would be a separate `migrate` service plus `condition: service_completed_successfully`. That condition is unreliable on Podman Compose — containers can start before the dependency has actually run (podman-compose #1330: a not-yet-started dependency reads as satisfied, and the init container can be started twice). Folding the idempotent DDL step into the start command keeps the dependency condition to `service_healthy`, which Podman Compose does implement, and keeps the stack at the two services the deployment actually needs. The release `CMD` is untouched; the compose file overrides it.

Rejected: (a) third `migrate` service with `service_completed_successfully` — ordering races on the target runtime; (b) baking `migrate` into a new `ENTRYPOINT` in the `Containerfile` — changes the image contract for every consumer, including plain `podman run`, where `DATABASE_URL`-less boot is now legitimate but the DDL step would then be unconditional; (c) `pre_start` hooks — compose-spec-only and not honored by Podman Compose.

The DDL is idempotent (upstream migration skips applied steps), so re-running it on every container start costs a round trip and is the mechanism by which a stack created against an empty volume gets its `logs` table.

### ClickHouse uses its `default` user with a mandatory password

The server service sets `CLICKHOUSE_PASSWORD` (required) and `CLICKHOUSE_DB`, and deliberately does **not** set `CLICKHOUSE_USER`, so the full-privilege `default` user is used with a password. The dashboard receives `CLICKHOUSE_USER=default` and the same password.

Rationale: the schema application issues DDL (`CREATE TABLE`, later `ALTER TABLE ... ADD COLUMN` on upgrade). A dedicated least-privilege user created through the image's `CLICKHOUSE_USER`/`CLICKHOUSE_PASSWORD`/`CLICKHOUSE_DB` triple is granted on that one database, and whether that grant covers everything the upstream migrator does is not something to bet a deployment on. `default` + password matches the already-documented runtime contract (`CLICKHOUSE_USER=default`) and the README's `podman run` example, so nothing about credential handling is new. The security exposure is bounded by the loopback-only port binding (D3).

Rejected: dedicated least-privilege ClickHouse user — privilege verification would have to be part of this change to be trustworthy; noted as a follow-up if a shared ClickHouse is ever fronted.

### `DATABASE_URL` becomes optional, keyed on configuration presence

`config/runtime.exs` configures `LoggerDashboard.Repo` only when `DATABASE_URL` is present (no raise), and `LoggerDashboard.Application` supervises it only when `Application.get_env(:logger_dashboard, LoggerDashboard.Repo)` is set. Configuration presence is the single switch both halves read, so there is no second flag to keep in sync.

Rationale: this is the minimum change that makes the release bootable next to ClickHouse alone while keeping every existing deployment working — a deployment that already exports `DATABASE_URL` gets the identical configured, supervised repo, so `mix test`, `mix ecto.*`, and dev/test are unaffected (both `config/dev.exs` and `config/test.exs` configure the repo, so tests still exercise the "configured" branch).

Rejected: (a) deleting the repo, `ecto_sql`/`postgrex`/`phoenix_ecto`, the `mix ecto.*` aliases, and the sandbox in `test/support/data_case.ex` — the honest end state, but it rewrites the dev/test bootstrap and belongs in its own change; (b) keeping the hard requirement — makes a two-service stack impossible; (c) a separate opt-out flag (`SKIP_POSTGRES=1`) — a second source of truth for something the config already answers.

### Secrets live in a gitignored `.env` with a committed `.env.example`

`SECRET_KEY_BASE`, `CLICKHOUSE_PASSWORD`, and `DASHBOARD_AUTH_TOKEN` are interpolated as `${VAR:?<message>}`, so a missing value aborts `podman compose up` with a message naming it, before any container exists. `DASHBOARD_AUTH_TOKEN` is required by the stack even though the app treats it as optional: the app's fallback is an ephemeral token that changes on every restart and is only recoverable from container logs, which is a trap for anything scripted against the stack.

Secrets never appear as literals in `compose.yaml`; defaults exist only for non-secret values (`PHX_HOST`, `CLICKHOUSE_DATABASE`, `DASHBOARD_PORT`). `.env` is added to `.gitignore`; `.env.example` documents each variable with its generating command (`mix phx.gen.secret`, `mix logger_dashboard.gen.token`, plus a note to use a high-entropy random password for ClickHouse).

### Health checks are declared in the compose file

Both services carry a `healthcheck:` block in `compose.yaml`; the dashboard's duplicates the `Containerfile` probe (`curl` → `200`/`401` on `/logs`, `curl` is present in the runner image) so `podman compose ps` reports it even when the image was built in the default OCI format and the image-level `HEALTHCHECK` was dropped.

ClickHouse's probe is not an unauthenticated `GET /ping`: it is `clickhouse-client --host 127.0.0.1 --user default --password "$CLICKHOUSE_PASSWORD" --query 'SELECT 1'` (shell form so the container's own env supplies the password), which is exactly the connection the dashboard will make. A wrong password therefore reports unhealthy before the DDL step is attempted, instead of surfacing as a migration failure. `start_period` covers ClickHouse's slow first boot; `restart: unless-stopped` on both services covers a dashboard that loses the race on a slow machine.

### ClickHouse ports bind to loopback only

`127.0.0.1:8123:8123` and `127.0.0.1:9000:9000`. The dashboard reaches ClickHouse over the compose network by service name, so the published ports exist only for host-local log producers and inspection. No `container_name` is set (avoids name collisions and keeps the project scoped to its directory) and no top-level `version:` key (obsolete in the compose spec).

## Risks / Trade-offs

- **DDL runs on every dashboard start** → It is idempotent and cheap; the alternative ordering mechanisms are unreliable on the target runtime (D1).
- **A non-loopback operator cannot use the stack** → `force_ssl` in `config/prod.exs` exempts only `localhost`/`127.0.0.1`, so any other host name over plain HTTP is redirected to HTTPS. Documented in the README section and covered by a spec scenario; the fix is TLS termination in front of the published port, not a config change here.
- **Remote log producers cannot write into the deployed ClickHouse** → Published ports are loopback-bound (D5). Documented; an operator publishing on a private interface is a one-line compose edit.
- **`.env` holds secrets in plaintext on the host** → Standard compose practice; the README instructs `chmod 600 .env` and the file is gitignored (D4).
- **Podman Compose drops the image-level `HEALTHCHECK`** → The compose-level probe makes the reported state deterministic regardless of build format (D6).
- **ClickHouse is single-node with a local volume** → No replication or HA, and `down --volumes` destroys the log store. Documented explicitly, including the recovery path of pointing the dashboard at an external ClickHouse via `CLICKHOUSE_URL`.
- **`SECRET_KEY_BASE` rotation invalidates existing sessions** → Expected for a stack restart with a regenerated secret; the README notes that reusing a stored `.env` keeps sessions valid.
- **Compose tooling differences** → The file sticks to the widely implemented subset (two services, `depends_on` with `service_healthy`, named volume, loopback ports, env interpolation with `:?`). Anything requiring newer compose-spec features was rejected in D1.

## Migration Plan

1. Land the `compose.yaml`, `.env.example`, `.gitignore` entry, README section, and the optional-Postgres app change together; there is no data migration.
2. Rollout: copy `.env.example` to `.env`, fill in the three secrets (`chmod 600 .env`), then `podman compose up --build`. Verify `/logs` prompts for the token and that `/analysis` and `/prune` respond.
3. Existing `podman run` deployments need no action: `DATABASE_URL` still configures and supervises the repo exactly as before.
4. Rollback: `podman compose down` (add `--volumes` to discard the ClickHouse data) and revert the app change. The manual `podman build` + `podman run` flow documented in the README remains valid throughout, so a stack rollout never depends on the compose file.
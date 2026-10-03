# Design

## Context

See `proposal.md` for motivation. Current state that shapes the removal:

- `LoggerDashboard.Repo` (`lib/logger_dashboard/repo.ex`) is `Ecto.Adapters.Postgres`; nothing queries it. Its only traces are the supervision child in `application.ex`, `ecto_repos: [LoggerDashboard.Repo]` in `config/config.exs`, per-env config in `config/dev.exs` and `config/test.exs`, the prod block in `config/runtime.exs`, and the `Phoenix.Ecto.CheckRepoStatus` plug in `endpoint.ex` (inside the dev-only `if code_reloading?`).
- `LoggerDashboard.Release` (`lib/logger_dashboard/release.ex`) is the generated `Ecto.Migrator` wrapper reading `Application.fetch_env!(@app, :ecto_repos)`. It has no callers; ClickHouse DDL runs through `rel/overlays/bin/migrate` → `ClickhouseExLogger.Utils.migrate/0`.
- `test/support/data_case.ex` provides only an SQL-sandbox `setup_sandbox/1` and an unused `errors_on/1`; no test does `use LoggerDashboard.DataCase`. `test/support/conn_case.ex` calls `LoggerDashboard.DataCase.setup_sandbox(tags)` in its setup, so it is the one real coupling to remove. `test/test_helper.exs` sets sandbox mode.
- `mix.exs` carries `phoenix_ecto`, `ecto_sql`, `postgrex`, an `ecto.setup`/`ecto.reset` alias pair, and a `test` alias prefix of `ecto.create`/`ecto.migrate`. `.formatter.exs` imports the `:ecto`/`:ecto_sql` formatter deps. `priv/repo/` holds an empty migrations dir and a commented `seeds.exs`.
- `README.md` documents `DATABASE_URL`/`POOL_SIZE`, a Postgres `podman run` example, and requires the DDL step to pass `DATABASE_URL`.
- Compose pieces are described in the sibling in-flight change `add-compose-deployment`, which stops at making `DATABASE_URL` optional. This change performs the full removal its Non-goals deferred; only one `container-image` delta should land.

## Goals / Non-Goals

**Goals:**

- Zero Postgres surface: no dependency, module, config, alias, plug, test helper, directory, or README mention remains.
- The release boots and the whole test suite runs with only ClickHouse reachable.
- A single declarative stack: `podman compose up --build` (docker-compatible) → working dashboard over single-node ClickHouse.

**Non-Goals:**

- Reworking the ClickHouse read/write paths, routes, or the token gate (unchanged).
- ClickHouse tuning, replication, TLS termination, or a reverse proxy.
- Migrating or preserving anything from the unused Postgres store (it held no dashboard data).
- Deleting the Phoenix-generated `priv/gettext/errors.*` catalogs, which reference Ecto message keys but are inert and shared phrasing (kept to avoid churn).

## Decisions

### Full removal, not optional configuration

Delete the repo, its config, and its dependencies outright, rather than the "configure only when `DATABASE_URL` is present" middle ground in `add-compose-deployment`.

Rationale: the user's requirement is that the repo does not use Postgres; keeping a supervised/conﬁgurable repo for a database nothing reads leaves dead configuration, a dead dependency graph, and a second boot path to test. Presence-gating would also force `ConnCase`/`DataCase` to keep sandbox plumbing that never runs. The honest end state is the smaller one.

Rejected: (a) presence-gated optional repo — carries all the surface with none of the use; (b) leaving deps in place while deleting only config — `mix deps.unlock --unused` (part of `precommit`) would keep failing and the Ecto warnings persist.

### `ConnCase` loses the sandbox; `DataCase` is deleted

`ConnCase.setup/1` drops the `LoggerDashboard.DataCase.setup_sandbox(tags)` call; `test/support/data_case.ex` and `test/test_helper.exs`'s sandbox line are removed. `priv/repo/` is deleted.

Rationale: no test uses `DataCase`; the only reference is the sandbox call in `ConnCase`, which exists solely for a database that is not queried. ClickHouse test isolation already works by tagging rows with a per-test `node` and deleting them in `on_exit` (observed across `log_read_test.exs`, `analysis_test.exs`, `log_live_test.exs`), so test correctness does not depend on the Ecto sandbox.

Rejected: keeping `DataCase` minus the sandbox for `errors_on/1` — unused; or keeping `ConnCase`'s sandbox call as a no-op — references a deleted module.

### `LoggerDashboard.Release` is deleted

Rationale: it exists only to run `Ecto.Migrator` over `ecto_repos`; with no Ecto repo it is dead code, and the ClickHouse schema is applied by `rel/overlays/bin/migrate` (`ClickhouseExLogger.Utils.migrate/0`). Removing it also removes the last compile reference to `:ecto_repos`.

### Compose: DDL folded into the dashboard start command

The dashboard service uses `command: ["/bin/sh", "-c", "/app/bin/migrate && exec /app/bin/server"]`, gated by `depends_on: clickhouse: {condition: service_healthy}`.

Rationale: the canonical third `migrate` service with `condition: service_completed_successfully` is unreliable on Podman Compose (a not-yet-started dependency reads as satisfied; podman-compose #1330). Folding the idempotent upstream migration into the start command keeps the dependency condition to `service_healthy`, which Podman Compose implements, and keeps the stack to the two services the deployment needs. The image `CMD` is untouched; the compose file overrides it. The DDL needs `CLICKHOUSE_*` and `SECRET_KEY_BASE` but no supervision tree and no Postgres.

Rejected: a third one-shot service (ordering race); baking `migrate` into a new `ENTRYPOINT` in the `Containerfile` (changes the image contract for plain `podman run` consumers); `pre_start` hooks (compose-spec-only, not honored by Podman Compose).

### ClickHouse uses its `default` user with a mandatory password

The server service sets `CLICKHOUSE_PASSWORD` (required) and `CLICKHOUSE_DB`, deliberately not `CLICKHOUSE_USER`, so the full-privilege `default` user is used with a password. The dashboard receives `CLICKHOUSE_USER=default`.

Rationale: schema application issues DDL (`CREATE TABLE`, later `ALTER TABLE ... ADD COLUMN`). Whether a dedicated least-privilege user's grant covers everything the upstream migrator does is not something to bet a deployment on; `default` + password matches the already-documented runtime contract. Exposure is bounded by loopback-only port binding.

Rejected: a dedicated least-privilege user — privilege verification would have to be part of this change to be trustworthy; a follow-up if a shared ClickHouse is ever fronted.

### Secrets live in a gitignored `.env` with a committed `.env.example`

`SECRET_KEY_BASE`, `CLICKHOUSE_PASSWORD`, and `DASHBOARD_AUTH_TOKEN` are interpolated as `${VAR:?<message>}`, aborting `podman compose up` with a message naming a missing value before any container exists. `DASHBOARD_AUTH_TOKEN` is required by the stack even though the app treats it as optional: the app's fallback is an ephemeral token that rotates per restart and is only recoverable from container logs. Defaults exist only for non-secret values (`PHX_HOST`, `CLICKHOUSE_DATABASE`, `DASHBOARD_PORT`). No `DATABASE_URL`/`POOL_SIZE` appears anywhere. `.env` is gitignored; `.env.example` documents each variable with its generating command.

### ClickHouse credentials ride in the dashboard's URL

The dashboard service is given `CLICKHOUSE_URL: http://default:${CLICKHOUSE_PASSWORD}@clickhouse:8123` and no separate `CLICKHOUSE_USER`/`CLICKHOUSE_PASSWORD`.

Rationale (established by running the stack, not by reading config): `AshClickhouse.Connection.clickhouse_opts/1` forwards only `:url`, `:interface`, and pool options to `ClickHouse.start_link/1` — it never passes `:username`/`:password`, and the `clickhouse` dep's HTTP interface has no auth options at all. So `CLICKHOUSE_USER`/`CLICKHOUSE_PASSWORD`, though documented and configured in `config/runtime.exs`, never reach the wire; every request goes out unauthenticated and a password-protected server rejects it with `Code: 194 ... (REQUIRED_PASSWORD)`. This is pre-existing, not introduced here: it is invisible against the default password-less server the dev/test stack uses. URL userinfo works because the client hands the URL to hackney, which converts userinfo into basic auth. Verified against the live stack: the DDL applies, `logs` and `schema_migrations` are created, and `/logs` renders rows.

Consequence: the password must avoid `/ : @ ? # & %` and whitespace to keep the URL well-formed, so `.env.example` recommends `openssl rand -hex 24`.

Rejected: (a) building the URL in `config/runtime.exs` from the three separate variables — preserves the env contract and hides the assembly, but adds Elixir changes to a change scoped to deployment files; (b) a password-less ClickHouse — simplest, but abandons the authenticated-readiness requirement and exposes logs to any local process; (c) patching `AshClickhouse.Connection` — the correct long-term fix, but a dependency change belonging in its own change.

### The start command halts on a failed schema bootstrap

The dashboard's command is `sh -c '<eval ClickhouseExLogger.Utils.migrate() halting on error> && exec /app/bin/server'`.

Rationale: `ClickhouseExLogger.Utils.migrate/1` logs a failed bootstrap and returns `{:error, reason}` without raising, and `bin/logger_dashboard eval` exits 0 regardless of the returned value. Observed consequence: with a wrong password, `/app/bin/migrate && exec /app/bin/server` proceeded to serve traffic against a store whose `logs` table never existed — every route answering `200` while rendering error pages, and the healthcheck passing because it authenticates natively via `clickhouse-client`. Matching the same entry point in a `case` and calling `System.halt(1)` on `{:error, _}` is what makes the "failed schema application keeps the service down" scenario true.

Rejected: (a) `/app/bin/migrate && exec /app/bin/server` as originally designed — silently serves a broken store; (b) probing the table afterwards with `Repo.query/1` — `eval` runs on a non-booted system, so it returns `{:error, NoClientError}` and exits 0 anyway.

### Health checks are declared in the compose file

Both services carry `healthcheck:`. The dashboard probe duplicates the `Containerfile` one (`curl` → `200`/`401` on `/logs`) so `podman compose ps` reports it even when the image is built in the default OCI format and the image-level `HEALTHCHECK` is dropped. The ClickHouse probe is `clickhouse-client --user default --password "$CLICKHOUSE_PASSWORD" --query 'SELECT 1'` (shell form), i.e. the authenticated connection the dashboard will make; a wrong password reports unhealthy before the DDL step is attempted. `start_period` covers ClickHouse's slow first boot; `restart: unless-stopped` covers a dashboard that loses a slow-machine race.

### ClickHouse ports bind to loopback only

`127.0.0.1:8123:8123` and `127.0.0.1:9000:9000`. The dashboard reaches ClickHouse by compose service name. No `container_name` (avoids collisions) and no top-level `version:` key (obsolete in the compose spec).

## Risks / Trade-offs

- **Removing a dependency graph breaks a hidden reference** → The comprehensive `rg` sweep found the full reference set before drafting; the exhaustive `mix precommit` (compile with warnings-as-errors, `deps.unlock --unused`, format, test) is the proof. `endpoint.ex`'s `CheckRepoStatus` plug is the one reference that would otherwise fail compilation once `phoenix_ecto` is gone.
- **Tests assumed sandbox isolation** → They never used it; each test cleans its own ClickHouse rows by `node` tag. A running ClickHouse is still required for the `:clickhouse`-tagged suite.
- **DDL runs on every dashboard start** → Idempotent and cheap; the alternative ordering mechanisms are unreliable on Podman Compose.
- **A non-loopback operator cannot use the stack over plain HTTP** → `force_ssl` in `config/prod.exs` exempts only `localhost`/`127.0.0.1`; documented, with TLS termination as the fix.
- **Remote log producers cannot reach the deployed ClickHouse** → Loopback-bound ports; documented, one-line compose edit to publish on a private interface.
- **Password is visible in container metadata** → URL userinfo means `podman inspect` and `podman compose config` print it. Accepted for this stack: the ClickHouse port is loopback-only, the value is in a `chmod 600` gitignored `.env`, and the alternative (no password) exposes logs to any local process. A dependency-level fix would remove this.
- **Documented `CLICKHOUSE_USER`/`CLICKHOUSE_PASSWORD` are inert** → Pre-existing and now recorded in the `container-image` delta. The env contract keeps working for a password-less server, which is what dev/test use.
- **Wrong credentials now keep the dashboard down in a restart loop** → Intended (the spec requires it) and visible: `podman compose logs dashboard` shows the schema bootstrap error. `ClickHouse.Interface.HTTP`'s own ping error is swallowed by the dep and is not relied upon.
- **`.env` holds secrets in plaintext on the host** → Standard compose practice; README instructs `chmod 600` and the file is gitignored.
- **ClickHouse is single-node with a local volume** → No HA, and `down --volumes` destroys the store; documented, including pointing at an external ClickHouse via `CLICKHOUSE_URL`.
- **Overlap with in-flight `add-compose-deployment`** → Its interim optional-Postgres step and `container-image` delta are superseded. Resolve by archiving that change unstarted when this one is accepted, or by discarding this change in favor of extending it; they must not both archive, as each would rewrite the same `container-image` requirement.

## Migration Plan

1. Land the removal and the compose stack together. No data migration: Postgres held no dashboard data, and the ClickHouse `logs` table is created by the stack's DDL step.
2. Rollout: copy `.env.example` to `.env`, fill in the three secrets (`chmod 600 .env`), then `podman compose up --build`. Verify `/logs` prompts for the token and `/analysis` and `/prune` respond.
3. Operators with an existing Go/Phoenix deployment that exported `DATABASE_URL` drop that variable; it is no longer read and setting it has no effect.
4. Rollback: `podman compose down` (add `--volumes` to discard ClickHouse data) and revert the commit. The manual `podman build` + `podman run` flow documented in the README remains valid.

## Open Questions

- Whether to archive `add-compose-deployment` as superseded or fold this change into it. Deferrable: it does not change the specs, approach, or tasks here, only which change record archives first.

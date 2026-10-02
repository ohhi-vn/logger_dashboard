# Tasks

## 1. Remove Postgres from application boot and config

- [x] 1.1 Delete `lib/logger_dashboard/repo.ex` (`LoggerDashboard.Repo`) and `lib/logger_dashboard/release.ex` (`LoggerDashboard.Release`); verify `rg "LoggerDashboard.Repo|LoggerDashboard.Release" lib config test` returns no hits after the remaining tasks and `mix compile --warnings-as-errors` succeeds
- [x] 1.2 Remove the `LoggerDashboard.Repo` child from the supervision list in `lib/logger_dashboard/application.ex`; verify the app boots (`mix run -e 'IO.puts(:ok)'`) and ClickHouse traffic still serves
- [x] 1.3 Remove `ecto_repos: [LoggerDashboard.Repo]` from `config/config.exs`, the `LoggerDashboard.Repo` block from `config/dev.exs` and `config/test.exs`, and the entire prod Postgres block (`DATABASE_URL` raise, `ECTO_IPV6`, `POOL_SIZE`, repo config) from `config/runtime.exs`; verify `mix compile --warnings-as-errors` succeeds
- [x] 1.4 Remove the `plug Phoenix.Ecto.CheckRepoStatus, otp_app: :logger_dashboard` line from `lib/logger_dashboard_web/endpoint.ex`; verify `mix phx.server` starts with no compile error (requires the dep removal in 2.1 first)
- [x] 1.5 Update `rel/overlays/bin/migrate.bat` to invoke `ClickhouseExLogger.Utils.migrate()` (matching `rel/overlays/bin/migrate`) so deleting `LoggerDashboard.Release` does not break the Windows release task; verify the file no longer names `LoggerDashboard.Release`

## 2. Remove Postgres dependencies and aliases

- [x] 2.1 Remove `phoenix_ecto`, `ecto_sql`, and `postgrex` from `mix.exs` `deps/0`, drop the `ecto.setup`/`ecto.reset` aliases and the `ecto.create --quiet`/`ecto.migrate --quiet` prefix from the `test` alias (leaving `setup: ["deps.get", "assets.setup", "assets.build"]` and a bare test run); verify `mix deps.get`, `mix deps.unlock --unused`, and `mix compile --warnings-as-errors` succeed
- [x] 2.2 Update `.formatter.exs`: drop `:ecto` and `:ecto_sql` from `import_deps` and the `subdirectories: ["priv/*/migrations"]` entry; verify `mix format --check-formatted` succeeds
- [x] 2.3 Delete `priv/repo/` (empty `migrations/` and commented `seeds.exs`); verify `rg "priv/repo|ecto_repos|Ecto\.Migrator" .` outside `openspec/`, `deps/`, `_build/` returns no hits

## 3. Remove Postgres test scaffolding

- [x] 3.1 Delete `test/support/data_case.ex`, remove the `LoggerDashboard.DataCase.setup_sandbox(tags)` call from `test/support/conn_case.ex`, and remove the `Ecto.Adapters.SQL.Sandbox.mode/2` line from `test/test_helper.exs`; verify `rg "DataCase|SQL.Sandbox|LoggerDashboard.Repo" test` returns no hits
- [x] 3.2 Run the suite against a running ClickHouse (`mix test`, `:clickhouse`-tagged tests included) and verify all pass, confirming per-test `node` cleanup still isolates tests without the Ecto sandbox

## 4. Add the Podman Compose stack

- [x] 4.1 Add `compose.yaml` at repo root: a `clickhouse` service (`clickhouse/clickhouse-server:26.9`, named volume, `127.0.0.1:8123:8123` and `127.0.0.1:9000:9000`, password from `.env`, authenticated `clickhouse-client` healthcheck) and a `dashboard` service (built from `Containerfile`, `depends_on: clickhouse: {condition: service_healthy}`, `command: ["/bin/sh","-c","/app/bin/migrate && exec /app/bin/server"]`, HTTP healthcheck, `restart: unless-stopped`); verify `podman compose config` resolves with no undefined variable and lists exactly two services
- [x] 4.2 Add `.env.example` listing `SECRET_KEY_BASE`, `DASHBOARD_AUTH_TOKEN`, `CLICKHOUSE_PASSWORD` as required (with `mix phx.gen.secret` / `mix logger_dashboard.gen.token` / high-entropy instructions) plus non-secret `PHX_HOST`, `CLICKHOUSE_DATABASE`, `DASHBOARD_PORT`, and add `.env` to `.gitignore`; verify `git check-ignore .env` reports it and a `compose.yaml`/`.env.example` grep for `DATABASE_URL|POOL_SIZE|postgres` returns no hits
- [x] 4.3 Copy `.env.example` to `.env`, fill the secrets, and run `podman compose up --build`; verify the dashboard answers on the published port, `/logs` prompts for the token, and `/analysis` and `/prune` respond
- [x] 4.4 Verify stack lifecycle: `podman compose down` then `up` keeps seeded log rows; `down --volumes` then `up` starts empty with the schema reapplied; `podman compose up` with a secret removed fails naming it before any container starts
- [x] 4.5 Carry the ClickHouse credentials in the dashboard's URL (`http://default:${CLICKHOUSE_PASSWORD}@clickhouse:8123`) instead of `CLICKHOUSE_USER`/`CLICKHOUSE_PASSWORD`, and restrict `.env.example` to a URL-safe password (`openssl rand -hex 24`, no `/ : @ ? # & %`); verify the dashboard's ClickHouse URL carries the password and `podman compose config` resolves it
- [x] 4.6 Make the dashboard start command halt on a failed schema bootstrap (`case ClickhouseExLogger.Utils.migrate() do {:ok, _} -> :ok; {:error, reason} -> System.halt(1) end && exec /app/bin/server`); verify a wrong password leaves the dashboard down with a non-zero exit and the bootstrap error in its logs, while correct credentials reach a running endpoint
- [x] 4.7 Prove reads against the protected store, not just HTTP status: insert a row over authenticated HTTP, confirm `/logs` renders it with the token and `/analysis` raises no data-layer error

## 5. Update documentation and prove the whole change

- [x] 5.1 Update `README.md`: add the Podman Compose deployment section (prerequisites, `.env` generation, up/down/logs, volume-reset semantics, plain-HTTP/`force_ssl` caveat), remove all `DATABASE_URL`/`POOL_SIZE`/Postgres references from the configuration table and `podman run`/DDL examples, and state the release needs only `SECRET_KEY_BASE` in prod; verify `rg -i "database_url|pool_size|postgres" README.md` returns no hits
- [x] 5.2 Remove now-inapplicable Postgres/Ecto guidance from `AGENTS.md` (the Ecto guidelines section and Postgres-flavored test notes); verify the remaining guidance still matches the ClickHouse-only stack
- [x] 5.3 Run `mix precommit` with a ClickHouse instance up and verify it passes end to end (compile warnings-as-errors, `deps.unlock --unused`, format, full test suite), then confirm `git status` shows `mix.lock` updated with the Ecto/Postgres packages removed

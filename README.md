# LoggerDashboard

Dashboard for logs shipped by [`clickhouse_ex_logger`](https://hex.pm/packages/clickhouse_ex_logger) into ClickHouse. View, filter, analyze, and prune logs per node or system-wide.

- `/logs` — browse logs (node scope, `*`/`?` text search, UTC datetime range, level)
- `/analysis` — level frequency, volume over time, per-node breakdown (AshDyan)
- `/prune` — delete by node or whole system with confirmation

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start ClickHouse (e.g. `podman run -d -p 8123:8123 clickhouse/clickhouse-server:26.9`)
* Run `mix clickhouse_ex_logger.migrate` to create the `logs` table (re-run after upgrades — it adds the `node` column)
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Authentication

Every route (`/`, `/logs`, `/analysis`, `/prune`) is behind one shared token. There are no user accounts: anyone with the token can prune.

Set the token before starting the app:

```bash
export DASHBOARD_AUTH_TOKEN=$(mix logger_dashboard.gen.token)   # 256-bit URL-safe token
```

Leave it unset and the app generates an ephemeral token at boot, keeps it in memory only, and logs it once:

```console
[dashboard_auth] DASHBOARD_AUTH_TOKEN is unset; generated an ephemeral token.
token: p0IT5ILGogM9yep1hjaehE66uwwMUrfG
```

It changes on every restart. In a container, read it back with `podman logs`.

Either credential form works:

```bash
curl -u "operator:$DASHBOARD_AUTH_TOKEN" http://localhost:4000/logs      # Basic (password = token)
curl -H "Authorization: Bearer $DASHBOARD_AUTH_TOKEN" http://localhost:4000/logs
```

A browser gets a `401` with a `WWW-Authenticate: Basic` challenge, so it prompts for a username and password — the password is the token and the username is ignored. Static assets stay public; they carry no data.

Tokens are compared in constant time and are never logged except for that one boot line.

## Container image

```bash
podman build -t logger-dashboard:latest .          # add --format docker for the HEALTHCHECK
docker build  -t logger-dashboard:latest .

podman run -d --name logger_dashboard -p 4000:4000 \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  -e DATABASE_URL=ecto://postgres:postgres@clickhouse:5432/logger_dashboard_prod \
  -e PHX_HOST=dashboard.example.com \
  -e CLICKHOUSE_URL=http://clickhouse:8123 \
  -e CLICKHOUSE_USER=default \
  -e CLICKHOUSE_PASSWORD=secret \
  -e DASHBOARD_AUTH_TOKEN="$(mix logger_dashboard.gen.token)" \
  logger-dashboard:latest
```

The image runs as `nobody`, listens on `$PORT` (default `4000`), and needs no Elixir or Node at runtime. `SECRET_KEY_BASE` and `DATABASE_URL` are required in prod — the boot fails naming whichever is missing.

Apply the ClickHouse DDL before the first start (the image has no Mix):

```bash
podman run --rm --network clickhouse \
  -e SECRET_KEY_BASE=... -e DATABASE_URL=... -e CLICKHOUSE_URL=... \
  logger-dashboard:latest /app/bin/migrate
```

## Demo data

Seed synthetic logs so `/logs`, `/analysis`, and `/prune` have something to show:

```bash
mix logger_dashboard.seed_logs --preset small            # 500 rows
mix logger_dashboard.seed_logs --preset medium           # 5000 rows
mix logger_dashboard.seed_logs --preset burst            # 20000 rows
```

Presets only set a row count; any explicit flag wins. Useful combinations:

```bash
# multi-node, round-robin (default) or --node-distribution random
mix logger_dashboard.seed_logs --count 5000 --nodes web@10.0.0.1,worker@10.0.0.2

# explicit UTC date range, error/warning only
mix logger_dashboard.seed_logs --from 2026-09-01T00:00:00Z --to 2026-09-08T00:00:00Z --levels error,warning

# reproducible run (same seed produces the same rows, except UUIDs)
mix logger_dashboard.seed_logs --count 1000 --seed 42
```

Preview without writing (`--dry-run`) prints counts per level and per node plus a
sample message. Seeding only inserts; clean up with `/prune`. In `prod` the task
requires `--allow-prod`.

## Configuration

| Variable | Default | Notes |
| --- | --- | --- |
| `DASHBOARD_AUTH_TOKEN` | generated per boot | Shared token for every route. Empty/unset generates an ephemeral one. |
| `PHX_SERVER` | unset | Set to `true` to serve HTTP (the container sets it). |
| `PORT` | `4000` | HTTP port. |
| `PHX_HOST` | `example.com` | Public host used for generated URLs. |
| `SECRET_KEY_BASE` | — | **Required in prod.** Raises at boot when unset. |
| `DATABASE_URL` | — | **Required in prod.** Raises at boot when unset. |
| `POOL_SIZE` | `10` | Postgres pool size. |
| `CLICKHOUSE_URL` | `http://localhost:8123` | |
| `CLICKHOUSE_USER` | `default` | |
| `CLICKHOUSE_PASSWORD` | empty | |
| `CLICKHOUSE_DATABASE` | `logger_dashboard_dev` | |

```elixir
# config/runtime.exs (env overrides)
config :clickhouse_ex_logger, ClickhouseExLogger.Repo,
  url: System.get_env("CLICKHOUSE_URL", "http://localhost:8123"),
  username: System.get_env("CLICKHOUSE_USER", "default"),
  password: System.get_env("CLICKHOUSE_PASSWORD", ""),
  database: System.get_env("CLICKHOUSE_DATABASE", "logger_dashboard_dev")
```

`ClickhouseExLogger.Repo` is supervised before the Endpoint. Missing configuration raises instead of silently defaulting.

## Releases

Run migrations **before** boot (no Mix in releases):

```bash
bin/logger_dashboard eval "ClickhouseExLogger.Utils.migrate()"
# or, from the container image
/app/bin/migrate
```

Then start with `PHX_SERVER=true bin/logger_dashboard start`.

## Warnings

- **Prune is async and irreversible.** ClickHouse applies `ALTER TABLE ... DELETE` as a background mutation; rows disappear after it completes. There is no rollback.
- **The token is shared, not per-user.** Anyone holding it can prune. Rotate by changing the env var (or restarting with no token).
- **Serve over TLS.** Basic/Bearer credentials are only base64-encoded. Terminate TLS in front of the container; the plain-HTTP dev setup is not safe on a network.
- **Message search is in-memory.** `*`/`?` wildcards filter in Elixir over the latest 1,000 ClickHouse-prefiltered rows (node/level/time push down). Tighten the time range for large log volumes.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

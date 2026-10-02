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

For a full deployment — dashboard plus ClickHouse in one command — see [Deployment](#deployment).

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

## Deployment

The stack is two services — the dashboard and a single-node ClickHouse. Nothing
else is required.

Prerequisites: Podman with Podman Compose (or Docker with Compose v2).

```bash
cp .env.example .env      # then fill in the three required secrets
chmod 600 .env
podman compose up --build
```

The dashboard is then on <http://localhost:4000> (`docker compose up --build`
works identically). Required secrets, and how to generate them:

| Variable | Generate with |
| --- | --- |
| `SECRET_KEY_BASE` | `mix phx.gen.secret` |
| `DASHBOARD_AUTH_TOKEN` | `mix logger_dashboard.gen.token` |
| `CLICKHOUSE_PASSWORD` | `openssl rand -hex 24` |

`podman compose up` aborts naming any missing variable before it creates a
container, so a stack never starts with a default or empty secret. Keep the
password free of `/ : @ ? # & %` and whitespace — it travels in the dashboard's
ClickHouse URL (see [Configuration](#configuration)), and hex output has none of
those characters.

Common commands:

```bash
podman compose ps             # service and health state
podman compose logs -f dashboard
podman compose down           # stop; log rows are kept
podman compose down --volumes # stop and DELETE all stored logs
```

`down --volumes` destroys the ClickHouse data volume. The next `up` recreates the
schema automatically, so the dashboard comes back empty but working.

Notes and caveats:

- **ClickHouse ports are loopback-only.** `8123` and `9000` bind to `127.0.0.1`
  so they are not reachable from another host. To let a remote node ship logs
  into it, publish the port on a private interface in `compose.yaml` and
  firewall it.
- **Plain HTTP on loopback only.** The release's `force_ssl` exempts just
  `localhost` and `127.0.0.1`; any other hostname over plain HTTP is redirected
  to HTTPS. Terminate TLS in front of the published port for remote access —
  the stack itself serves no TLS.
- **Single node, no replication.** All logs live in one local volume.
- **Pointing at an existing ClickHouse instead** works too: drop the `clickhouse`
  service from `compose.yaml` and set `CLICKHOUSE_URL` on the dashboard to your
  instance.

## Container image

To run the image without compose:

```bash
podman build -t logger-dashboard:latest .          # add --format docker for the HEALTHCHECK
docker build  -t logger-dashboard:latest .

podman run -d --name logger_dashboard -p 4000:4000 \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  -e PHX_HOST=dashboard.example.com \
  -e CLICKHOUSE_URL=http://clickhouse:8123 \
  -e DASHBOARD_AUTH_TOKEN="$(mix logger_dashboard.gen.token)" \
  logger-dashboard:latest
```

The image runs as `nobody`, listens on `$PORT` (default `4000`), and needs no
Elixir or Node at runtime. `SECRET_KEY_BASE` is the only variable required in
prod — the boot fails naming it when missing. There is no other database: the
dashboard reads only ClickHouse.

Apply the ClickHouse DDL before the first start (the image has no Mix):

```bash
podman run --rm --network clickhouse \
  -e SECRET_KEY_BASE=... -e CLICKHOUSE_URL=... \
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
| `CLICKHOUSE_URL` | `http://localhost:8123` | Service URL, e.g. `http://clickhouse:8123`. |
| `CLICKHOUSE_USER` | `default` | See the note below — not forwarded to the client. |
| `CLICKHOUSE_PASSWORD` | empty | See the note below — not forwarded to the client. |
| `CLICKHOUSE_DATABASE` | `logger_dashboard_dev` | |

For a ClickHouse that requires authentication, put the credentials in the
URL's userinfo:

```
CLICKHOUSE_URL=http://default:<password>@clickhouse:8123
```

`CLICKHOUSE_USER` and `CLICKHOUSE_PASSWORD` are read into the repo config but
are **not** passed on to the HTTP client, which receives only the URL — so on a
password-protected server they authenticate nothing. This is why the compose
stack builds the URL with the credentials in it. Prefer a password without
`/ : @ ? # & %` so the URL stays well-formed.

```elixir
# config/runtime.exs (env overrides)
config :clickhouse_ex_logger, ClickhouseExLogger.Repo,
  url: System.get_env("CLICKHOUSE_URL", "http://localhost:8123"),
  username: System.get_env("CLICKHOUSE_USER", "default"),
  password: System.get_env("CLICKHOUSE_PASSWORD", ""),
  database: System.get_env("CLICKHOUSE_DATABASE", "logger_dashboard_dev")
```

`ClickhouseExLogger.Repo` is supervised before the Endpoint. Note that a wrong
host or database fails at query time rather than at boot; only wrong
credentials against a password-protected server reach it at all if they are in
the URL.

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
- **The ClickHouse password shows up in container metadata.** It travels in the dashboard's URL, so `podman inspect` and `podman compose config` print it. Keep `.env` at `chmod 600`.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

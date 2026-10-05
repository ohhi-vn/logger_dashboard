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

In a container, read it back with `podman logs`.

### Signing in

A browser that opens a gated page without a session is redirected to `/login`, which
asks for the token. A correct token signs you in and returns you to the page you were
heading for; **Sign out** in the header ends the session and sends you back to `/login`.
Static assets stay public; they carry no data.

The session is a cookie, and it records a **digest** of the token rather than the token
itself — the cookie is signed, not encrypted, so anyone holding it can read it.

### Accessing it from a script

There is no `Authorization` header path: neither HTTP Basic nor `Bearer` authenticates
anything. Sign in once and reuse the cookie jar:

```bash
# 1. Sign in. The CSRF token is in the form, so scrape it out.
BASE=http://localhost:4000
CSRF=$(curl -s -c jar.txt "$BASE/login" \
  | grep -o '<input name="_csrf_token"[^>]*>' \
  | sed -n 's/.*value="\([^"]*\)".*/\1/p')

# 2. Exchange the token for the session cookie.
curl -s -b jar.txt -c jar.txt -X POST "$BASE/login" \
  --data-urlencode "_csrf_token=$CSRF" \
  --data-urlencode "session[token]=$DASHBOARD_AUTH_TOKEN" \
  -o /dev/null -w '%{http_code}\n'      # 302

# 3. Now the jar is authenticated.
curl -s -b jar.txt "$BASE/logs"
```

A request that does not accept HTML — `curl` with an explicit `Accept: application/json`,
say — gets a bare `401` rather than the login page, so a script can tell "wrong" from
"here is a form for a browser".

### Sessions and restarts

A session cannot outlive the token that established it: the digest is re-checked on
every request and on every LiveView mount, so **replacing the token signs every open
session out**. With the default ephemeral token that means a restart does it, because
the token is regenerated. Set a pinned `DASHBOARD_AUTH_TOKEN` — as the compose stack
already requires — if you want sessions to survive a deploy. Sessions otherwise expire
after eight hours.

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

The dashboard is then on <http://localhost:5051> (`docker compose up --build`
works identically). The stack serves the dashboard on `5051` and ClickHouse on
`8124`/`9001` (loopback only), so it runs alongside dev (`4000`/`8123`)
without clashing.
Required secrets, and how to generate them:

| Variable | Generate with |
| --- | --- |
| `SECRET_KEY_BASE` | `mix phx.gen.secret` |
| `DASHBOARD_AUTH_TOKEN` | `mix logger_dashboard.gen.token` |
| `CLICKHOUSE_PASSWORD` | `openssl rand -hex 24` |

`podman compose up` aborts naming any missing variable before it creates a
container, so a stack never starts with a default or empty secret. To connect
as a non-`default` user, set `CLICKHOUSE_USER` to the provisioned name; the
dashboard and the ClickHouse healthcheck both use it (default `default`).
The password travels in the dashboard's effective ClickHouse URL
(see [Configuration](#configuration)); hex output avoids reserved URL
characters entirely, and other values are percent-encoded at boot.

Common commands:

```bash
podman compose ps             # service and health state
podman compose logs -f dashboard
podman compose down           # stop; log rows are kept
podman compose down --volumes # stop and DELETE all stored logs
```

`down --volumes` destroys the ClickHouse data volume and the saved-configuration
volume. The next `up` recreates the schema automatically, so the dashboard comes back
empty but working, and any policy you saved on the prune page is gone with the
configured defaults back in force.

Notes and caveats:

- **ClickHouse ports are loopback-only.** In the compose stack `8124` and `9001`
  bind to `127.0.0.1` (via a mounted server config, since the server defaults
  are `8123`/`9000`) so they are not reachable from another host. To let a
  remote node ship logs into it, publish the port on a private interface in
  `compose.yaml` and firewall it.
- **Plain HTTP on loopback only.** The release's `force_ssl` exempts just
  `localhost` and `127.0.0.1`; any other hostname over plain HTTP is redirected
  to HTTPS. Terminate TLS in front of the published port for remote access —
  the stack itself serves no TLS.
- **Single node, no replication.** All logs live in one local volume.
- **Run one dashboard instance.** Saved configuration is a file in that
  container's own volume, so a second instance keeps its own policy and runs its
  own schedule — and both prune the same ClickHouse. See
  [Scheduled retention](#scheduled-retention).
- **Pointing at an existing ClickHouse instead** works too: drop the `clickhouse`
  service from `compose.yaml` and set `CLICKHOUSE_URL` on the dashboard to your
  instance.

## Scheduled retention

`/prune` can arm a policy that deletes logs older than a retained age, across every
node, once a day with nobody watching. Every run is logged with the scope and cutoff it
applied.

**Saving an enabled policy does not arm it.** "Save policy" asks for confirmation
first, naming the scope and retained age it would reach; only "Confirm and arm"
writes the policy and starts the schedule. Until then the policy exists nowhere — not
saved, not in force, and not pending — and cancelling discards it with the policy in
force left untouched. Turning the policy *off*, or removing the saved one, needs no
confirmation: neither can delete anything.

The policy in force can come from two places:

- the environment (`RETENTION_ENABLED`, `RETENTION_RUN_AT`, `RETENTION_KEEP`), which
  is what applies until you save one from the page;
- a policy you confirmed on `/prune`, which outranks the environment and **survives a
  restart and a redeploy**.

The page states which of the two is in force. "Remove saved policy" deletes the saved
one, so the environment's policy is in force again for this run and every later one.
The dashboard never rewrites the environment it was deployed with.

Saved policies live in `TASK_CONFIG_DIR` (`/app/task_config` in the compose
stack, on the `task-config-data` volume). That volume is what makes a saved policy
outlive a redeploy; without it the directory sits in the container's writable layer and
is lost when the container is recreated. If the directory cannot be written the
dashboard still serves, background tasks fall back to the configured policy, and the
prune page says so rather than reporting a save that did not happen.

Two things to know before arming it:

- **The schedule is not made retroactive.** A dashboard that was down when the run
  time passed does not prune on the next boot; it waits for the next occurrence. A
  saved policy is durable, and catch-up is still refused.
- **One instance.** A second dashboard keeps its own saved policy and fires its own
  deletes at the same ClickHouse. There is no leader election, by design.

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

The image runs as `nobody`, listens on `$DASHBOARD_PORT` (default `4000`), and needs no
Elixir or Node at runtime. `SECRET_KEY_BASE` is the only variable required in
prod — the boot fails naming it when missing. There is no other database: the
dashboard reads only ClickHouse.

Configuration you save through the UI goes to `/app/task_config` unless
`TASK_CONFIG_DIR` says otherwise. That path is inside the container, so pass a
volume if it has to outlive the container:

```bash
podman run -d --name logger_dashboard -p 4000:4000 \
  -v logger-dashboard-config:/app/task_config \
  -e TASK_CONFIG_DIR=/app/task_config \
  ... logger-dashboard:latest
```

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
| `DASHBOARD_PORT` | `4000` (`5051` in the compose stack) | HTTP port: same value sets the container listen port and the published host port in compose. |
| `PHX_HOST` | `example.com` | Public host used for generated URLs. |
| `SECRET_KEY_BASE` | — | **Required in prod.** Raises at boot when unset. |
| `CLICKHOUSE_URL` | `http://localhost:8123` | Service URL; the compose stack uses bare `http://clickhouse:8124` and the release injects credentials (next note). A URL that already carries userinfo is used verbatim. |
| `CLICKHOUSE_USER` | `default` | Honored via the effective URL below. |
| `CLICKHOUSE_PASSWORD` | empty | Honored via the effective URL below. |
| `CLICKHOUSE_DATABASE` | `cluster_log` | |
| `TASK_CONFIG_DIR` | `<release dir>/task_config` | Where configuration you save from the UI is kept. Put it on persistent storage. |
| `RETENTION_ENABLED` | `false` | `true`/`1`/`yes`/`on` arms [scheduled retention](#scheduled-retention) from the environment. |
| `RETENTION_RUN_AT` | `03:00 UTC` | `HH:MM UTC`. |
| `RETENTION_KEEP` | `7d` | Retained age: `1h`, `6h`, `12h`, `1d`, `3d`, `7d`, `30d`, `90d`. An unrecognised value disables retention rather than failing the boot. |

For a ClickHouse that requires authentication, set the user and password
alongside a bare URL and the release builds the effective URL at boot:

```
CLICKHOUSE_URL=http://clickhouse:8124
CLICKHOUSE_USER=my_user
CLICKHOUSE_PASSWORD=<password>
```

`CLICKHOUSE_USER` and `CLICKHOUSE_PASSWORD` are injected as percent-encoded
URL userinfo by `config/runtime.exs` (`LoggerDashboard.ClickhouseUrl`),
because the HTTP client receives only the URL — the separate keys alone
authenticate nothing. A `CLICKHOUSE_URL` that already carries userinfo
(e.g. `http://my_user:<password>@my-host:8123` for an external server) wins
verbatim. Hex passwords avoid reserved URL characters entirely; other values
are encoded at boot.

```elixir
# config/runtime.exs (env overrides) — url is the effective URL built from
# the three values above via LoggerDashboard.ClickhouseUrl
clickhouse_url = LoggerDashboard.ClickhouseUrl.build(base_url, user, password)

config :clickhouse_ex_logger, ClickhouseExLogger.Repo,
  url: clickhouse_url,
  username: System.get_env("CLICKHOUSE_USER", "default"),
  password: System.get_env("CLICKHOUSE_PASSWORD", ""),
  database: System.get_env("CLICKHOUSE_DATABASE", "cluster_log")
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
- **Serve over TLS.** The session cookie is a bearer credential: anyone who copies it is authenticated for the rest of its life. Terminate TLS in front of the container; the plain-HTTP dev setup is not safe on a network. `SameSite=Lax` blocks the obvious cross-site POST, but it is not a substitute for TLS.
- **Message search is in-memory.** `*`/`?` wildcards filter in Elixir over the latest 1,000 ClickHouse-prefiltered rows (node/level/time push down). Tighten the time range for large log volumes.
- **The ClickHouse password shows up in container metadata.** It travels in the dashboard's URL, so `podman inspect` and `podman compose config` print it. Keep `.env` at `chmod 600`.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

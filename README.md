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
```

Then start with `PHX_SERVER=true bin/logger_dashboard start`.

## Warnings

- **Prune is async and irreversible.** ClickHouse applies `ALTER TABLE ... DELETE` as a background mutation; rows disappear after it completes. There is no rollback.
- **No auth in MVP.** The dashboard (especially `/prune`) is open. Put it behind `Plug.BasicAuth`, VPN, or network isolation until auth is added.
- **Message search is in-memory.** `*`/`?` wildcards filter in Elixir over the latest 1,000 ClickHouse-prefiltered rows (node/level/time push down). Tighten the time range for large log volumes.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

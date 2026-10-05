# Proposal

## Why

`podman compose up --build` from a clean checkout does not yield a working dashboard, while `mix phx.server` in dev works. The compose stack must serve literally on host `5051` (dashboard) and `8124`/`9001` (ClickHouse) — same port inside and outside the container — so it runs alongside dev (`4000`/`8123`) without clashing.

## What Changes

- Add a `build` section to the `dashboard` service so `podman compose up --build` builds `logger-dashboard:latest` from the repo `Containerfile` on a clean checkout.
- Dashboard literal same-port: pass `DASHBOARD_PORT` (default `5051`) into the container so the release listens on `5051`, publish `127.0.0.1:${DASHBOARD_PORT:-5051}:${DASHBOARD_PORT:-5051}` (default `5051:5051`), and probe that port in the compose healthcheck. Default serves `http://localhost:5051`; dev/`podman run` default stays `4000`.
- ClickHouse literal same-port: configure the server to listen on `8124` (HTTP) and `9001` (native) via command-line overrides (`-- --http_port=8124 --tcp_port=9001`), publish `127.0.0.1:8124:8124` and `127.0.0.1:9001:9001` (loopback only), point the dashboard URL at `clickhouse:8124`, and check health on the new ports. Inter-service traffic stays on the service name.
- Single-source env defaults with `CLICKHOUSE_DATABASE` pinned to `cluster_log` across `compose.yaml`, `.env.example`, and `runtime.exs`; remove the hardcoded database override that ignores `CLICKHOUSE_DATABASE`.
- Keep `SECRET_KEY_BASE`, `DASHBOARD_AUTH_TOKEN`, `CLICKHOUSE_PASSWORD` required-fail-fast (`:?`) behavior and loopback-only posture unchanged.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `compose-deployment`: fix published ports, add build-from-Containerfile, and unify env defaults so `up --build` serves on the published port from a clean checkout.
- `container-image`: clarify the runtime port variable (`DASHBOARD_PORT`, default `4000`) and that `CLICKHOUSE_DATABASE` is honored at runtime.

## Impact

- `compose.yaml`, `config/runtime.exs`, `.env.example`, `README.md` deployment/docs sections.
- No Ash query, LiveView, pruning, or auth logic changes. No new dependencies or services. Existing volumes (`clickhouse-data`, `task-config-data`) and secret names unchanged.

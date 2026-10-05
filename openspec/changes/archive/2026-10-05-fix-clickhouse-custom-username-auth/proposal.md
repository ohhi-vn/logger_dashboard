# Proposal

## Why

Setting `CLICKHOUSE_USER` to anything other than `default` breaks the stack: the dashboard still connects as `default` and ClickHouse rejects it with code 194 `REQUIRED_PASSWORD`. Operators cannot use a dedicated ClickHouse user.

## What Changes

- Build the dashboard's effective ClickHouse URL from `CLICKHOUSE_URL` + `CLICKHOUSE_USER` / `CLICKHOUSE_PASSWORD`, injecting percent-encoded userinfo when the URL carries none, so a custom username reaches the wire without forking `ash_clickhouse` or `clickhouse`.
- Use the same `CLICKHOUSE_USER` in `compose.yaml` for the dashboard URL and the ClickHouse healthcheck instead of hardcoded `default`, with `default` as the fallback.
- Provision/document the custom user consistently: `CLICKHOUSE_USER` (default `default`), safe password guidance, and updated README / `.env.example` / config comments.
- Keep single-command `podman compose up --build` behavior and loopback-only ports unchanged.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `compose-deployment`: credential requirement changes from "URL carries password for hardcoded `default` user; `CLICKHOUSE_USER`/`CLICKHOUSE_PASSWORD` pair never sent" to "effective URL carries the configured `CLICKHOUSE_USER` and password; healthcheck and server provisioning use the same user".

## Impact

- Affected: `config/runtime.exs` (effective URL builder), `config/test.exs` (same env behavior under test), `compose.yaml` (dashboard URL, healthcheck, clickhouse env comments), `.env.example`, `README.md` (Configuration + Deployment sections), `config/config.exs` comments.
- No change to `AshClickhouse`, `clickhouse`, or `clickhouse_ex_logger` dependencies; DDL stays upstream.
- Behavior change for existing deployments that set `CLICKHOUSE_USER`: previously ignored (always `default`), now honored — operators relying on the ignore must set `CLICKHOUSE_USER=default` or a userinfo URL.

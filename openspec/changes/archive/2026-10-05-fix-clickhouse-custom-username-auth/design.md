# Design

## Context

See `proposal.md` for why. Current state verified in-tree:

- `AshClickhouse.Connection.clickhouse_opts/1` forwards only `:url` (plus pool opts) to `ClickHouse.start_link/1`; `AshClickhouse.Repo.config_to_conn_opts/1` likewise drops `:username`/`:password`. The `clickhouse` HTTP client (`ClickHouse.Interface.HTTP.Client`) takes no username/password option and passes the URL straight to `:hackney`, which derives basic auth solely from URL userinfo.
- Hence `config :clickhouse_ex_logger, ClickhouseExLogger.Repo, username:/password:` never reaches the wire. This repo works around it by embedding `http://default:<pass>@clickhouse:8124` in `compose.yaml`, with the same hardcoded `default` in the ClickHouse healthcheck.
- Setting `CLICKHOUSE_USER=custom` therefore provisions (via the ClickHouse image) a custom user while the dashboard, healthcheck, and migration still try `default` → code 194 `REQUIRED_PASSWORD` for `default`, matching the reported log.

Constraints: DDL stays upstream; do not fork `ash_clickhouse`/`clickhouse`; keep `JSONCompactEachRow` pin and loopback-only ports.

## Goals / Non-Goals

**Goals:**
- A configured `CLICKHOUSE_USER` is honored end-to-end (dashboard queries, `ClickhouseExLogger.Utils.migrate/0`, compose healthcheck) with no dep changes.
- Explicit userinfo URLs keep working (external ClickHouse path in README).
- Passwords with reserved characters do not break URL parsing.

**Non-Goals:**
- Creating/managing ClickHouse users or grants beyond what the official server image already does with `CLICKHOUSE_USER`/`CLICKHOUSE_PASSWORD`/`CLICKHOUSE_DB`.
- Supporting multiple ClickHouse users, per-request credentials, or TLS client certs.
- Changing query, pruning, or retention behavior.

## Decisions

1. **Build the effective URL at config time in `config/runtime.exs` (same helper reused by `config/test.exs`).**
   - Parse `CLICKHOUSE_URL`; if `userinfo` is already present, keep it verbatim. Otherwise inject `URI.encode(user, &URI.char_unreserved?/1):URI.encode(pass, ...)` + `@` before host. Default user `default` when unset; empty password means no userinfo injection beyond user alone only when password non-empty, else user-only form.
   - Rationale: single choke point before `ClickhouseExLogger.Repo` boots; covers `mix phx.server`, releases, `mix test`, and external-ClickHouse (`CLICKHOUSE_URL` to own host) without touching supervision or deps.
   - Alternative rejected: patch `AshClickhouse.Connection` via fork/dep override — upstream-owned invariant, higher lifecycle cost for one field.

2. **Parameterize `compose.yaml` on `CLICKHOUSE_USER`.**
   - Dashboard: `CLICKHOUSE_URL=http://${CLICKHOUSE_USER:-default}:<encoded-pass>@clickhouse:8124` pattern (encoding handled where compose interpolation allows; if compose cannot encode, pass user/pass through and let `runtime.exs` do the injection from a bare host URL instead — prefer the latter so encoding lives in one place).
   - ClickHouse healthcheck: `clickhouse-client --user "${CLICKHOUSE_USER:-default}" --password "$CLICKHOUSE_PASSWORD"`.
   - Keep `CLICKHOUSE_USER` optional with `:-default` so existing `.env` files without it keep working; document it as optional in `.env.example`.
   - Alternative rejected: hard-require `CLICKHOUSE_USER` — breaks existing deployments that only set password.

3. **Keep separate `:username`/`:password` repo config for documentation, but treat URL as source of truth on the wire.**
   - Continue writing both keys in `runtime.exs` so logs/config dumps show intent, with a comment stating only the URL authenticates. Avoids implying a second auth path that does not exist.

4. **Docs and example env updated together.**
   - `.env.example`, README Configuration/Deployment, and `config/config.exs` comments state the userinfo rule, the `default` default, and the hex-password guidance (now with encode fallback so non-hex still works).

## Risks / Trade-offs

- [Risk] Compose interpolation cannot percent-encode → double-encoding or raw special chars in URL → Mitigation: do injection in Elixir (`runtime.exs`), keep compose URL as bare host when user/pass are separate, or encode in Elixir only.
- [Risk] Existing deployments that set `CLICKHOUSE_USER` expecting it to be ignored will now change user → Mitigation: default stays `default`; migration note tells operators to set `CLICKHOUSE_USER=default` explicitly or verify the custom user exists with DDL rights.
- [Risk] ClickHouse image semantics for `CLICKHOUSE_USER` (creates user vs. renames default) differ by server version → Mitigation: verify against pinned `clickhouse/clickhouse-server:26.9` during implementation; document observed behavior; healthcheck + failed-bootstrap halt already surface mismatch.
- [Risk] Password visible in `podman inspect` via URL (pre-existing) → Trade-off accepted and already documented; no new exposure, same channel.

## Migration Plan

- Deploy: add/keep `CLICKHOUSE_USER` (or leave unset for `default`), `CLICKHOUSE_PASSWORD`, `CLICKHOUSE_DATABASE`; `podman compose up --build`.
- Rollback: set `CLICKHOUSE_USER=default` with the previous password, or restore prior `compose.yaml` + `runtime.exs`; no data migration (named volume untouched).
- Verification: `podman compose ps` healthy, dashboard boot shows successful migrate, `/logs` returns rows with custom user; wrong password keeps dashboard down (existing halt-on-failed-bootstrap).

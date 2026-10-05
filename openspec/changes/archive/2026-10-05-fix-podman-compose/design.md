# Design

## Context

See `proposal.md` for why. Current state (observed in repo):
- `compose.yaml` dashboard publishes `127.0.0.1:${DASHBOARD_PORT:-5051}:5051` but never passes `DASHBOARD_PORT` into the container, so the release listens on its default `4000` (`config/runtime.exs`) while the published container port `5051` has no listener.
- ClickHouse publishes `8124:8124` / `9001:9001` while the server listens on its defaults `8123`/`9000` and the dashboard dials `clickhouse:8123`. Literal host ports `8124`/`9001` are required, so the server itself must be reconfigured to listen there.
- Dashboard has `image: logger-dashboard:latest` with no `build` section, so `up --build` on a clean checkout has nothing to build despite docs promising it.
- `config/runtime.exs` sets the Repo twice; the trailing block hardcodes `database: "cluster_log"`, ignoring `CLICKHOUSE_DATABASE`. Defaults drift: compose `cluster_log` vs `.env.example` `logger_dashboard` vs hardcoded `cluster_log`.
- Health probes query `:4000` (dashboard) and default native port (ClickHouse) inside the container, matching app/server defaults but not the required `5051` / `8124`+`9001`.

Constraint: keep two services, loopback-only posture, fail-fast `:?` secrets, named volumes, and upstream-owned DDL unchanged.

## Goals / Non-Goals

**Goals:**
- `cp .env.example .env` + fill secrets + `podman compose up --build` works from a clean checkout and serves on `http://localhost:5051` by default, literally `5051:5051` / `8124:8124` / `9001:9001` on loopback.
- Dev (`mix phx.server` on `4000`/`8123`) and standalone `podman run` defaults stay untouched; the compose stack lives on its own host ports.
- `DASHBOARD_PORT` remains a single knob in compose: same var sets the container listen port (via env) and both sides of the publish, so any override stays same-port.

**Non-Goals:**
- No TLS termination, replication, multi-instance, or auth-model changes.
- No Ash / LiveView / pruning logic changes. No new services or dependencies.

## Decisions

1. **Dashboard same-port via env: container listens where it publishes.**
   Set `DASHBOARD_PORT: ${DASHBOARD_PORT:-5051}` in the dashboard environment and publish `127.0.0.1:${DASHBOARD_PORT:-5051}:${DASHBOARD_PORT:-5051}` (default `5051:5051`); probe that port in the compose healthcheck. Rationale: the release already listens on `$DASHBOARD_PORT`, so injecting the same var the publish uses keeps host and container literally equal for every override with no image change. Alternative (fixed `5051:5051` + fixed env) rejected: loses the override knob. Alternative (host-only remap `5051→4000`) rejected per operator direction: host ports must equal container ports.

2. **Add `build: { context: ., dockerfile: Containerfile }` to `dashboard`, keep `image: logger-dashboard:latest`.**
   Rationale: satisfies the existing "built from the repository Containerfile" requirement for both podman and docker compose with one tag. Alternative (separate image names per tool) adds nothing.

3. **Reconfigure ClickHouse to listen on `8124`/`9001` and publish literally.**
   Pass positional config overrides (`-- --http_port=8124 --tcp_port=9001`; `clickhouse-server --help`: args after `--` rewrite config), publish `127.0.0.1:8124:8124` and `127.0.0.1:9001:9001`, point the dashboard URL at `http://default:${CLICKHOUSE_PASSWORD}@clickhouse:8124`, and check health on the new ports (`clickhouse-client --port 9001`, HTTP ping on `:8124`). Rationale: the image does not switch listen ports via env; a mounted config file was rejected because bind mounts fail when the checkout lives outside the container VM's shared paths. Inter-service traffic follows the service name to `:8124`. Alternative (host-only remap `8124→8123`) rejected per operator direction.

4. **Merge the duplicated Repo config in `runtime.exs` into one block.**
   Single `config :clickhouse_ex_logger, ClickhouseExLogger.Repo` reading `url` from `CLICKHOUSE_URL`, `username`/`password` from env, `database` from `CLICKHOUSE_DATABASE` with one default shared with compose and `.env.example`. Delete the trailing hardcoded `database: "cluster_log"` block. Rationale: root-causes custom-database-ignored; keeps URL-userinfo auth invariant intact.

5. **Unify defaults to `CLICKHOUSE_DATABASE=cluster_log`.**
   Use `cluster_log` in all three places (`compose.yaml`, `.env.example`, `runtime.exs`) and document it. Rationale: this is the value the stack already exercises via the compose default and the current runtime fallback, so existing volumes keep working; avoids silent empty-store vs missing-table confusion.

## Risks / Trade-offs

- [Risk] Nonstandard ClickHouse ports depend on the image's `--` config-override form; a future entrypoint change could stop forwarding them → Mitigation: e2e verifies `8124/ping` plus authenticated `clickhouse-client --port 9001`, which fail loudly instead of serving stale defaults.
- [Risk] `DASHBOARD_PORT` in compose now moves both host and container ports; image/Containerfile default stays `4000`, so `podman compose config` with an override must be re-checked → Mitigation: single-var-both-sides form plus compose healthcheck on the same var; document compose `5051` vs standalone/dev `4000`.
- [Risk] Changing the shared database default renames the store for someone → Mitigation: pinned to the dominant existing default `cluster_log`; note `down --volumes` reset behavior; no data migration attempted.

## Migration Plan

1. Edit `compose.yaml` (build, `DASHBOARD_PORT` env + same-port publish + `:5051` probe, ClickHouse `--` port overrides + literal publish + `:8124` URL + new healthcheck ports), merge `runtime.exs` Repo block, set `auto_start: false`, unify defaults to `cluster_log`, update `.env.example` (`DASHBOARD_PORT=5051`), README deployment table.
2. Validate: `podman compose config`, then `podman compose up --build` from clean state with fresh `.env`; curl `http://localhost:5051/login` → 200; `curl 127.0.0.1:8124/ping` → ok; `clickhouse-client --host 127.0.0.1 --port 9001` → 1; `podman compose ps` shows healthy.
3. Rollback: revert the four files; volumes are untouched so `down`/`up` restores prior mapping.

## Open Questions

None. Port values and default database are pinned by specs above; any residual doc wording is editorial during apply.

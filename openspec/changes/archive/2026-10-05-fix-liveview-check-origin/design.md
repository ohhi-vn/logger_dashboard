# Design

## Context

See proposal.md Why. Current state observed in the repo:

- `lib/logger_dashboard_web/endpoint.ex` declares `socket "/live", Phoenix.LiveView.Socket` with no per-transport `check_origin`, so the endpoint-level `check_origin` governs both websocket and longpoll.
- `config/dev.exs` already sets `check_origin: false`, so a plain `mix phx.server` dev loop is exempt; the failing origin in the log (`http://127.0.0.1:5051`, `http://localhost:5051`, port `5051` = compose `DASHBOARD_PORT` default) points at the release path.
- `config/runtime.exs` prod block sets `url: [host: host ...]` from `PHX_HOST` (default `example.com`; compose defaults it to `localhost`) and sets no `check_origin`, so Phoenix falls back to checking `Origin` against the URL host. Accessing via the other loopback name always mismatches; with the `example.com` default both loopbacks mismatch.
- `config/prod.exs` `force_ssl` already exempts `hosts: ["localhost", "127.0.0.1"]`, confirming both loopbacks are first-class entry points; `check_origin` is the one that was not given the same treatment.

## Goals / Non-Goals

**Goals:**
- Release accepts `/live` socket origins from `localhost`, `127.0.0.1`, and `PHX_HOST` with origin checking still on.
- One fix covers both transports (websocket + longpoll) and any `DASHBOARD_PORT`.

**Non-Goals:**
- No change to dev (`check_origin: false`), the `force_ssl` exemption list, compose ports, or `PHX_HOST` defaulting.
- No per-socket transport options in `endpoint.ex`; no new env vars.

## Decisions

- **Endpoint-level `check_origin` allowlist in `config/runtime.exs` prod block** (e.g. `["//localhost", "//127.0.0.1", "//#{host}"]`, deduplicated) over per-transport options in `endpoint.ex`: one setting covers both transports, lives next to the `url: [host: ...]` it must stay consistent with, and can be derived from the already-read `PHX_HOST`. Alternative (socket-level `check_origin` in `endpoint.ex`) would split host knowledge across two files and needs a compile-time value for a runtime env.
- **Host-only `//host` entries (no port/scheme pinning)** over explicit `//host:port` entries: Phoenix host-only entries match any port/scheme, so custom `DASHBOARD_PORT` values and `http` vs `https` (including TLS-terminating proxies) keep working. Alternative (pin port 5051) would re-break every `DASHBOARD_PORT` override.
- **Keep checking enabled; reject `check_origin: false` in prod**: disabling would silence the log but drop socket CSRF protection. The allowlist preserves the security property while fixing the false rejection. Changing only `url[host]` was also rejected: `localhost` vs `127.0.0.1` can never both equal one host value.

## Risks / Trade-offs

- [Risk] `//localhost` / `//127.0.0.1` accept any port and any scheme on loopback → Mitigation: loopback is already the only published interface (`127.0.0.1:...` publish, `force_ssl` exemption); a foreign page cannot present a loopback `Origin` from a victim browser without already running on the host.
- [Risk] Operators behind a reverse proxy on a public name forget to set `PHX_HOST` → Mitigation: the `//#{host}` entry tracks whatever `PHX_HOST` is set to; default docs already tell operators to set it, and foreign-origin rejection remains visible in logs rather than silent.
- [Risk] Duplicate entry when `PHX_HOST` is `localhost` → Mitigation: deduplicate the list (`Enum.uniq`) so config stays clean for the default compose case.

## Migration Plan

- Change is config-only in the release: rebuild/redeploy the image (or `podman compose up --build`); no ClickHouse DDL, no volume changes.
- Rollback: revert the `check_origin` lines and redeploy; behavior returns to host-only checking.

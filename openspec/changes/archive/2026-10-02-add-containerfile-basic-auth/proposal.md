# Proposal

## Why

The dashboard ships with no `Containerfile` and no auth (README warns `/prune` is openly destructive). Operators today must hand-roll images and front the app with VPN/`Plug.BasicAuth` themselves. A first-party container build plus minimal token gate makes the release (`bin/logger_dashboard start`) safely deployable.

## What Changes

- Add a multi-stage `Containerfile` (podman/docker compatible) at repo root that builds assets (`mix assets.deploy`), builds a Mix release, and runs it as non-root with `PHX_SERVER=true`.
- Add token-based access control in front of all dashboard routes (`/`, `/logs`, `/analysis`, `/prune`, plus `/dev` when enabled): unauthenticated browsers are asked for a token; requests without a valid token are rejected with `401`.
- Support two token sources:
  - Predefined via env (`DASHBOARD_AUTH_TOKEN`) read in `config/runtime.exs`.
  - Auto-generated at boot when env is absent, using Elixir built-ins (`:crypto.strong_rand_bytes/1` + `Base.url_encode64`), printed once to stdout/log and kept in memory (ephemeral, rotates on restart).
- Add a minimal token entry UX (HTTP Basic/Bearer challenge — no user accounts, no sessions beyond the gate) and document image build/run + auth env vars in `README`.
- Add a small built-in mix task/util (e.g. `mix logger_dashboard.gen.token`) to generate a token offline for operators to inject via env.

## Capabilities

### New Capabilities

- `container-image`: reproducible OCI image build and runtime contract for the Phoenix release (build stages, non-root, required env, ports, health behavior, ClickHouse connectivity).
- `dashboard-auth`: single shared-token gate protecting dashboard routes, with env-predefined or boot-generated token, constant-time verification, and token entry/rotation semantics.

### Modified Capabilities

- None. No existing spec REQUIREMENTS change; auth wraps all routes uniformly and containerization does not alter log viewing/analysis/pruning behavior.

## Impact

- Affected code: `lib/logger_dashboard_web/router.ex` (auth pipeline/plug), `lib/logger_dashboard_web/endpoint.ex` (ordering if needed), `config/runtime.exs` (+ `config/config.exs` defaults), new auth plug + token util/task under `lib/`, new `Containerfile` (+ `.containerignore`/`.dockerignore` update) at root.
- APIs/systems: all browser routes gain a `401` gate when token is set; container runtime requires `SECRET_KEY_BASE`, `DATABASE_URL` (prod), `CLICKHOUSE_*`, `PORT`/`PHX_HOST`; health/static asset behavior must keep working behind the gate or via explicit exclusion.
- Dependencies: no new Hex deps — use built-ins (`:crypto`, `Plug.BasicAuth`-style `Plug.Conn` helpers or hand-rolled constant-time compare) and base Elixir/OTP image only.

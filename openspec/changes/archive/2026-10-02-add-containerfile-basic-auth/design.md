# Design

## Context

See `proposal.md` Why. Current state (observed): no `Containerfile`/`Dockerfile`; `mix.exs` builds a Bandit-served Phoenix 1.8 app with `mix assets.deploy` and Mix releases; `config/runtime.exs` already reads `PORT`, `PHX_SERVER`, `SECRET_KEY_BASE`, `DATABASE_URL`, `CLICKHOUSE_*` at boot and raises on missing prod secrets; `router.ex` has a single open `:browser` pipeline (`/`, `/logs`, `/analysis`, `/prune`) with no auth; README explicitly warns "No auth in MVP — put it behind `Plug.BasicAuth`, VPN, or network isolation". Specs: `specs/container-image/spec.md` (OCI build/runtime contract) and `specs/dashboard-auth/spec.md` (shared-token gate, env or boot-generated).

## Goals / Non-Goals

**Goals:**
- One `Containerfile` that works with both `podman` and `docker`, reuses the existing release + `runtime.exs` env contract, and documents build/run.
- Minimal token gate with zero new Hex deps, covering browser pages and LiveView sockets, operable in containers via env or `podman logs`.

**Non-Goals:**
- No per-user accounts, roles, sessions UI, password reset, OAuth, or LiveDashboard SSO — single shared token only.
- No ClickHouse DDL changes, no Ash query changes, no dashboard UX redesign beyond the `401` challenge.
- No Kubernetes manifests, CI pipelines, or image registry publishing.

## Decisions

- **Containerfile: 3-stage (builder → assets → runner) on official Elixir/OTP + Debian-slim.**
  Builder (`hexpm/elixir:<otp>-erlang-<elixir>-debian-<ver>-slim`) installs build tools + Node (for esbuild/tailwind fetch), runs `mix deps.get`, `mix compile`, `mix assets.deploy`, `mix release`. Runner is minimal Debian-slim with only runtime libs (libstdc++, openssl, ca-certificates), non-root `app` user, `COPY --from=builder --chown=app:app`. Rationale: matches `mix phx.gen.release` Dockerfile conventions, keeps image small, avoids Alpine musl/Bandit/nif surprises. Alternative (single-stage or Alpine) rejected: bloats image and risks NIF/glibc issues.
- **Auth mechanism: custom `LoggerDashboardWeb.Plugs.DashboardAuth` checking HTTP Basic password OR Bearer token against one shared secret, wired as a `:browser` pipeline plug plus `on_mount` guard.**
  Accept `Authorization: Basic <base64(user:token)>` (username ignored, password is the token) and `Authorization: Bearer <token>` so both browser challenge and `curl -H` work. Browser gets `401` + `WWW-Authenticate: Basic realm="logger_dashboard"` which makes the browser natively "ask for token". Rationale over `Plug.BasicAuth` alone: `Plug.BasicAuth` forces username/password mental model and hardcodes realm handling; a 30-line custom plug supports Bearer for API/curl and keeps Basic compat. Alternative (full login form + session) rejected: needs session store, CSRF, LiveView form work for zero benefit at this scale.
- **Token resolution in `runtime.exs`, storage in app env (memory only).**
  `DASHBOARD_AUTH_TOKEN` non-empty → `Application.put_env(:logger_dashboard, :dashboard_auth_token, value)`; absent/empty → generate `:crypto.strong_rand_bytes(24)` + `Base.url_encode64(padding: false)` (≈192 bits) at boot, `Logger.info` once with `[dashboard_auth]` marker, never log again. Verification reads app env per request (supports test override). Rationale: follows existing `runtime.exs` secrets pattern, ephemeral-by-default is safe for containers, no disk persistence to leak. Alternative (persist to volume/file) rejected: creates secret-at-rest handling burden.
- **Verification: `Plug.Crypto.secure_compare/2` with UTF-8 normalization, no logging.**
  Reject missing/mismatched identically (`401`, empty body, same headers). No token in logs/errors. Rationale: `Plug.Crypto` is already a transitive dep via Phoenix; constant-time compare is the only correct choice for shared secrets.
- **LiveView coverage: plug for HTTP + `on_mount` for sockets.**
  Router pipeline plug covers initial page loads; an `on_mount(:ensure_authenticated)` hook attached to `LogLive`, `AnalysisLive`, `PruneLive` (via shared `use` or explicit `on_mount`) re-checks the session/token so a direct websocket connect without HTTP auth fails. `Plug.Static` intentionally stays before auth (public digested assets only, no data). Rationale: LiveView sockets bypass router plugs after upgrade; without `on_mount` the gate is bypassable. Alternative (Endpoint-level plug covering static too) rejected: would break cache-friendly asset serving and complicate health checks.
- **Offline generator: `mix logger_dashboard.gen.token` (built-ins only).**
  Same `:crypto` + Base pipeline, `--length` option defaulting to 32 bytes, prints to stdout. Rationale: satisfies "generate in runtime by utils (built-in)" for both boot-time and offline workflows with one code path; `mix phx.gen.secret` alternative rejected because its output is tied to `SECRET_KEY_BASE` semantics and length, not dashboard tokens.

## Risks / Trade-offs

- [Risk] Shared token leaks via shoulder-surfing, chat, or `podman logs` retention → Mitigation: document rotation (restart or change env), prefer env-injected long-lived tokens in production, treat boot-generated tokens as dev/single-session only.
- [Risk] `WWW-Authenticate: Basic` sends token as base64 on every request → Mitigation: require TLS in production (`force_ssl` already set,Runner exposes HTTP behind TLS-terminating proxy); document that plain-HTTP + Basic is dev-only.
- [Risk] Static assets stay public (by design) → Mitigation: assets contain no data, only JS/CSS; accepted and documented.
- [Risk] Elixir/OTP base image pin drifts → Mitigation: pin exact `hexpm/elixir` tag matching local `elixir --version`, add comment on how to bump with `mix.exs` `elixir: "~> 1.17"`.
- [Risk] Boot-generated token is invisible if log driver drops stdout → Mitigation: also emit via `Logger.info` (goes to configured backends) and document `podman logs --tail` retrieval; prod guidance is to always set env.

## Migration Plan

1. Land `Containerfile` + `.containerignore`, auth plug + pipeline wiring + `runtime.exs` token resolution + generator task + README updates.
2. Deploy: build image, set `SECRET_KEY_BASE`, `DATABASE_URL`, `CLICKHOUSE_*`, `PHX_HOST`, and `DASHBOARD_AUTH_TOKEN` (prod) — or read boot token from logs (dev). Run `bin/logger_dashboard eval "ClickhouseExLogger.Utils.migrate()"` before first start per README.
3. Verify: unauthenticated `curl -I /logs` → `401` + `WWW-Authenticate`; authenticated with Basic/Bearer → `200`; restart without env → old token `401`, new token `200`.
4. Rollback: revert image tag to pre-change build (no DB or DDL changes, so rollback is image-only; rotating the token on revert is expected).

## Open Questions

- None blocking. Deferrable: whether to add a `/healthz` endpoint excluded from auth for orchestrator probes (current specs require no health endpoint; add only if probes fail against `401`).

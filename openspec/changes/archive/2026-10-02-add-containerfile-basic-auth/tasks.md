# Tasks

## 1. Token auth core

- [x] 1.1 Add `LoggerDashboard.DashboardAuth` token util (generate via `:crypto.strong_rand_bytes` + `Base.url_encode64`, `resolve/0` reading app env) and verify `mix test test/logger_dashboard/dashboard_auth_test.exs` passes for generate length/entropy and env-vs-generated resolution
- [x] 1.2 Add `mix logger_dashboard.gen.token` task wrapping the util and verify `mix logger_dashboard.gen.token` prints one URL-safe token and exits zero
- [x] 1.3 Wire token resolution into `config/runtime.exs` (`DASHBOARD_AUTH_TOKEN` non-empty wins, else boot-generate + single `Logger.info`) and verify `MIX_ENV=test mix run --no-halt -e` boot logs token once and `Application.get_env(:logger_dashboard, :dashboard_auth_token)` is set
- [x] 1.4 Add `LoggerDashboardWeb.Plugs.DashboardAuth` plug (Basic-password-or-Bearer check, `Plug.Crypto.secure_compare`, `401` + `WWW-Authenticate: Basic realm="logger_dashboard"` on failure, no token logging) and verify plug unit test passes for missing/wrong/valid Basic and Bearer credentials

## 2. Router and LiveView gating

- [x] 2.1 Pipe dashboard routes through auth (`:browser` pipeline plug or `:authenticated` pipeline applied to `/`, `/logs`, `/analysis`, `/prune`, `/dev/*`) and verify unauthenticated `GET /logs` returns `401` with `WWW-Authenticate` via `Phoenix.ConnTest`
- [x] 2.2 Add `on_mount` auth guard for `LogLive`, `AnalysisLive`, `PruneLive` reusing the same token check and verify LiveView test with unauthenticated socket connect is denied while authenticated mount renders
- [x] 2.3 Add conn-level auth tests for valid env token (Basic + Bearer → `200`) and empty-env fallback (empty token rejected, generated token accepted), verifying no response body or log contains the expected token

## 3. Container image

- [x] 3.1 Add multi-stage `Containerfile` (pinned `hexpm/elixir` builder: deps.get/compile/assets.deploy/release; slim runner, non-root `app` user, `ENTRYPOINT` running migrations note + `CMD bin/logger_dashboard start`) and verify `podman build -f Containerfile -t logger-dashboard:plan .` completes
- [x] 3.2 Add `.containerignore` (exclude `_build/`, `deps/`, `cover/`, `doc/`, `tmp/`, `.git/`, local `priv/static/assets/`) and verify build context excludes them via `podman build` output / context check
- [x] 3.3 Verify runtime contract: run image with required env (`SECRET_KEY_BASE`, `DATABASE_URL`, `CLICKHOUSE_*`, `PHX_HOST`, `PORT`, `DASHBOARD_AUTH_TOKEN`) and verify `curl -I /logs` without token → `401`, with token → `200`, and missing `SECRET_KEY_BASE`/`DATABASE_URL` fails fast with named error
- [x] 3.4 Verify ephemeral-token path in container: run without `DASHBOARD_AUTH_TOKEN`, capture token from `podman logs`, verify it authenticates, then restart and verify old token → `401` and new logged token → `200`

## 4. Docs and precommit

- [x] 4.1 Update `README` (image build/run commands for podman+docker, full env table, auth behavior, token retrieval via logs, offline generator usage, TLS-behind-proxy note) and verify commands copy-paste against the new `Containerfile`
- [x] 4.2 Start ClickHouse (`podman run -d -p 8123:8123 clickhouse/clickhouse-server:26.9`), run `mix clickhouse_ex_logger.migrate`, then verify `mix precommit` passes and new auth tests are not tagged `:clickhouse` unless they need it

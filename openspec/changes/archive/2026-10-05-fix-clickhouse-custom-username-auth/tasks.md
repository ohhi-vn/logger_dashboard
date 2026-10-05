# Tasks

## 1. Effective ClickHouse URL

- [x] 1.1 Add URL-with-userinfo builder in `config/runtime.exs` (reused by `config/test.exs`) that preserves existing userinfo and otherwise injects percent-encoded `CLICKHOUSE_USER` (default `default`) + `CLICKHOUSE_PASSWORD`, and verify with `mix run --no-start -e` printing effective URLs for default user, custom user, pre-existing userinfo, and reserved-character password cases
- [x] 1.2 Wire the builder into `config :clickhouse_ex_logger, ClickhouseExLogger.Repo` in `runtime.exs` and `test.exs` while keeping `:username`/`:password` keys with a comment that only the URL authenticates, and verify with `MIX_ENV=test mix run --no-start -e 'IO.inspect(Application.get_env(:clickhouse_ex_logger, ClickhouseExLogger.Repo))'` showing the effective URL
- [x] 1.3 Add unit coverage for the builder (default fallback, custom user, userinfo preserved, percent-encoding) and verify with `mix test <new-test-file>`

## 2. Compose stack wiring

- [x] 2.1 Update `compose.yaml` dashboard `CLICKHOUSE_URL` and ClickHouse healthcheck to use `${CLICKHOUSE_USER:-default}` instead of hardcoded `default`, keep loopback ports and `clickhouse:8124` host, and verify with `podman compose config` rendering both a default-user and a custom-user `.env`
- [x] 2.2 Align `clickhouse` service env/comments so `CLICKHOUSE_USER` provisioning matches the dashboard user, and verify with `podman compose up --build` against pinned `clickhouse/clickhouse-server:26.9` showing healthy ClickHouse and successful schema bootstrap for a custom user
- [x] 2.3 Regression-check wrong-password behavior (dashboard exits non-zero, serves no traffic, ClickHouse unhealthy) and verify with container exit code and `podman compose ps` output

## 3. Docs and example env

- [x] 3.1 Update `.env.example`, `README.md` Configuration/Deployment, and `config/config.exs` comments to document optional `CLICKHOUSE_USER`, userinfo-wins rule, and password guidance, and verify by reading the rendered sections and `podman compose config` with an unset user defaulting to `default`

## 4. Verification

- [x] 4.1 Run custom-user end-to-end (`CLICKHOUSE_USER=<custom>` + password): `podman compose up --build`, open `/logs` and `/analysis` returning rows with no 194 error, and verify via dashboard plus `podman compose logs dashboard`
- [x] 4.2 Run `mix precommit` with a running ClickHouse (including `:clickhouse`-tagged tests) and verify zero failures

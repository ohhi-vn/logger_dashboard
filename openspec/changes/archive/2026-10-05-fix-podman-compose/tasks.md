# Tasks

## 1. Compose stack fix

- [x] 1.1 Add `build: { context: ., dockerfile: Containerfile }` to the `dashboard` service in `compose.yaml` and verify `podman compose config` shows the build section with image `logger-dashboard:latest`
- [x] 1.2 Wire `DASHBOARD_PORT` (default `5051`) into the dashboard container and publish literally `127.0.0.1:${DASHBOARD_PORT:-5051}:${DASHBOARD_PORT:-5051}` with the compose healthcheck on that port, and verify `podman compose config` shows default `5051:5051` plus the env var
- [x] 1.3 Configure ClickHouse to listen on `8124`/`9001` via command-line overrides, publish literally `127.0.0.1:8124:8124` and `127.0.0.1:9001:9001`, point `CLICKHOUSE_URL` at `clickhouse:8124`, and verify `podman compose config` plus `curl 127.0.0.1:8124/ping` and authenticated `clickhouse-client --port 9001`

## 2. Runtime config fix

- [x] 2.1 Merge the duplicated `ClickhouseExLogger.Repo` blocks in `config/runtime.exs` into one block reading `CLICKHOUSE_URL`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`, and `CLICKHOUSE_DATABASE`, and verify `mix compile --warnings-as-errors` passes and boot with a custom `CLICKHOUSE_DATABASE` migrates/reads that database
- [x] 2.2 Pin `CLICKHOUSE_DATABASE` default to `cluster_log` across `compose.yaml`, `.env.example`, and `runtime.exs` and verify `rg CLICKHOUSE_DATABASE` shows that value in all three places

- [x] 2.3 Set `config :clickhouse_ex_logger, auto_start: false` so the 0.3.x dependency does not start a second `ClickhouseExLogger.Repo` alongside the dashboard supervisor, and verify the release boots without `table name already exists`

## 3. Docs alignment

- [x] 3.1 Update `README.md` deployment/container sections and `.env.example` so the compose stack documents dashboard `http://localhost:5051`, ClickHouse host `8124`/`9001` loopback with container ports matching, `DASHBOARD_PORT` same-port semantics, and database default `cluster_log`, and verify documented defaults equal the compose/runtime defaults

## 4. End-to-end verification

- [x] 4.1 Bring the stack up from a clean checkout (`cp .env.example .env`, fill secrets, `podman compose up --build`), and verify `podman compose ps` reports healthy, `http://localhost:5051/login` serves, `127.0.0.1:8124/ping` answers, and `/logs` returns rows instead of auth/missing-table errors
- [ ] 4.2 Run `mix precommit` with a running ClickHouse and verify the suite passes without port, database, or credential regressions
  - Known status 2026-10-05: 397/398 pass. Single failure `AnalysisTest` "rolls NULL into unknown" is data-dependent and pre-existing (shared `cluster_log` table holds 32k accumulated rows; the empty-filter frequency scan window covers only the oldest parts, so fresh NULL/probe rows never appear in labels — verified at limits 1k and 50k). Not caused by this change (analysis/insert paths untouched; insert path byte-identical between dep 0.1.0 and 0.3.0). Left open deliberately; fix test isolation separately.

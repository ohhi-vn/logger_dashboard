# Tasks

## 1. Release origin allowlist

- [x] 1.1 Set endpoint-level `check_origin` in the `config/runtime.exs` prod block to `["//localhost", "//127.0.0.1", "//#{host}"]` (deduplicated) alongside the existing `url: [host: host ...]`, keeping dev `check_origin: false` untouched, and verify `mix compile --warnings-as-errors` passes and the file contains the allowlist
- [x] 1.2 Confirm no other endpoint or socket config overrides the allowlist (endpoint `/live` transports, `config.exs`, `prod.exs`) and verify by grepping for `check_origin` that only dev (`false`) and the new prod allowlist remain

## 2. Verification

- [x] 2.1 Boot the compose stack and open the dashboard at both `http://localhost:<port>` and `http://127.0.0.1:<port>`, and verify neither produces `Could not check origin` errors and LiveView becomes interactive (no longpoll `_mount_attempts` retry loop)
- [x] 2.2 Run `mix precommit` with ClickHouse available (per project context: upstream DDL via `mix clickhouse_ex_logger.migrate`) and verify it passes, fixing any format/compile/test issue it reports

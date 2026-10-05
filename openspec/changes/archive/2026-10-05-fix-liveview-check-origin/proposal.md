# Proposal

## Why

Accessing the dashboard at `http://localhost:5051` or `http://127.0.0.1:5051` (the documented compose entry points) fills the log with `Could not check origin for Phoenix.Socket transport` errors and the LiveView falls back to a longpoll reconnect loop (`_mount_attempts` climbing past 400 with `_mounts: 0`). The pages never establish a LiveView connection, so the dashboard is unusable from one of its two documented loopback addresses no matter which one the operator picks.

## What Changes

- Configure the release/prod endpoint's `check_origin` so LiveView socket connections (`/live`, websocket and longpoll) accept the loopback origins the stack actually serves on: `localhost` and `127.0.0.1` (any port/scheme), plus the configured `PHX_HOST`.
- Keep origin checking enabled (no `check_origin: false` outside dev); only the allowlist widens.
- Leave `config/dev.exs` (`check_origin: false`) and the `force_ssl` loopback exemption unchanged.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `compose-deployment`: extend the deployment contract that already publishes the dashboard on loopback, defaults `PHX_HOST` to `localhost`, and exempts `localhost`/`127.0.0.1` from force-SSL — with the requirement that the release accepts LiveView socket origins from both loopback hosts plus `PHX_HOST`.

## Impact

- Affected code: `config/runtime.exs` prod endpoint block (source of `check_origin`); no endpoint module, router, LiveView, or compose topology changes expected.
- APIs/dependencies: none; uses the existing Phoenix `check_origin` option.
- Systems: compose stack (`PHX_HOST`, `DASHBOARD_PORT`) and any release deployed behind `PHX_HOST`; dev `mix phx.server` path is already exempt via `check_origin: false` and is unaffected.

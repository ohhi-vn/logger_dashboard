# Proposal

## Why

The dashboard works, but `/` still serves the unused Phoenix boilerplate home and there is no shared navigation, so operators reach Logs, Analysis, and Prune only by typing URLs. Node scoping is single-node only, so investigating an incident across a few replicas means repeated manual queries. Separately, `mix assets.build` cannot run on macOS at all: the downloaded Tailwind 4.3.0 binary is killed by the OS with `SIGKILL (Code Signature Invalid)`, which blocks CSS builds and `mix setup`.

## What Changes

- Add a real dashboard homepage at `/` that links to Logs, Analysis, and Prune, replacing the Phoenix marketing page.
- Add a persistent cross-page navigation shell (home link, tool links, active-page marker, theme toggle) used by every page.
- Extend the log node filter from a single node to one-or-more nodes entered as a comma-separated list, applied on the Logs viewer and the Analysis page.
- Keep Prune's single-node/all-nodes safety model, adapting only its internals to the shared multi-value filter representation (a prune still targets exactly one node or the whole system, with explicit confirmation).
- Fix `mix assets.build` on macOS by ad-hoc re-signing the downloaded Tailwind binary before it is executed, without changing the Tailwind version.
- Polish the UI of all pages (filter forms, log rows, empty/error states) within the shared shell.

No public HTTP API or database schema changes. No breaking changes.

## Capabilities

### New Capabilities
- `dashboard-shell`: dashboard homepage and persistent cross-page navigation shared by all pages.
- `asset-build`: local asset builds (`mix assets.build` / `assets.setup` / `assets.deploy`) succeed on macOS despite the downloaded Tailwind binary's invalid code signature.

### Modified Capabilities
- `log-viewing`: the node scope accepts one or more nodes instead of a single node.
- `log-analysis`: the analysis scope accepts one or more nodes instead of a single node.

## Impact

- `lib/logger_dashboard/logs/filter.ex`: node becomes a list; predicate becomes `node IN (...)`; comma-separated parsing.
- `lib/logger_dashboard/logs/log_read.ex`, `analysis.ex`, `prune.ex`: adapt to the node-list representation; Prune keeps single-node/all scope semantics.
- `lib/logger_dashboard_web/live/log_live/index.ex`, `analysis_live/index.ex`, `prune_live/index.ex`: forms, node inputs, and UI polish.
- `lib/logger_dashboard_web/components/layouts.ex`: app shell with navigation; `controllers/page_html/home.html.heex` + `page_controller.ex`: homepage.
- `mix.exs` aliases plus a small Mix task that ad-hoc signs the Tailwind binary; `config/dev.exs` watcher for the same signing on `mix phx.server`.
- Tests: `filter_test.exs`, `log_read_test.exs`, `analysis_test.exs`, `prune_test.exs`, `log_live_test.exs`, `analysis_live_test.exs`, `prune_live_test.exs`, `page_controller_test.exs`, plus new shell tests.

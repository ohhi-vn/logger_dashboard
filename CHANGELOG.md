# Changelog

All notable changes to the Logger Dashboard are documented here, grouped by
date and derived from the project's OpenSpec change archive
(`openspec/changes/archive/`). Each entry cites its archive slug. The project
does not tag releases; the version in `mix.exs` (`0.3.0`) has not been bumped
per change.

> Note: changes dated 2026-10-19 and 2026-10-20 are complete in the working
> tree but not yet committed to git.

## 2026-10-20

### Added

- Analysis page laid out as one responsive breakdown grid — by level, by node, volume over time in that order — with the by-node breakdown in its own narrower column, bounded-height result tables that scroll with a pinned header, fixed-height charts that line up across cards, readable chart-style labels (URL identifiers unchanged), the bucket control sharing the range row, and the active node scope stated through the node options alone (`compact-analysis-node-breakdown`).

### Changed

- Logs, Analysis, and Prune render one shared filter-control set (node badges, level toggles, search, range) instead of three drifted copies (`unify-filters-charts-and-prune-flow`).
- Search is case-insensitive and multi-term (space-separated terms combined with AND); a term without a wildcard matches anywhere in the message, and a whole-phrase wildcard stays one phrase. **BREAKING:** searches that previously matched nothing (differing case, bare term requiring an exact message) now match (`unify-filters-charts-and-prune-flow`).
- Every Analysis breakdown offers a chart-style control with the choice kept in the URL so shared links reproduce the charts; the by-node breakdown gains a chart beside its table, and a style the data cannot represent falls back visibly (`unify-filters-charts-and-prune-flow`).
- Prune becomes a guided flow — choose the scope, set the cutoff, review, confirm — with a live review step (row count, per-node split, sample rows) and a confirmation that states the resolved instants and affected nodes (`unify-filters-charts-and-prune-flow`).

## 2026-10-19

### Changed

- Retention cadence follows the retained age: hour-valued ages (1h/6h/12h) prune every hour on the hour (UTC) instead of waiting for the daily run, so a "keep 1 hour" policy no longer holds up to a full extra day of logs; day-valued ages still run once daily at the configured time (`retention-cadence-follows-age`).

## 2026-10-12

### Changed

- Node scoping becomes badge-only on every page: the comma-separated node text input is removed and a `Select all nodes` action returns to whole-system scope **BREAKING** (`improve-logs-prune-analysis-ui`).
- Filter changes auto-apply through the URL params with a `Refresh` action; the `Apply filters`, `Reset`, and `Prune all logs` buttons are gone **BREAKING** (`improve-logs-prune-analysis-ui`).
- Log row expansion is multi-open (expanding a row no longer collapses the previous one), with `Expand all messages` / `Collapse all messages` shortcuts for the current page **BREAKING** (`improve-logs-prune-analysis-ui`).
- Prune defaults to whole-system scope instead of single-node; the `All time` shortcut explicitly permits an unbounded delete of the scope in effect, with preview and confirm still required **BREAKING** (`improve-logs-prune-analysis-ui`).

## 2026-10-07

### Added

- Multi-level filter on Logs and Analysis: zero, one, or more of `error`/`warning`/`info`/`debug` with OR semantics; empty or `all` applies no level predicate; the `level` URL param accepts a comma-separated list (`multi-log-level-filter`).

### Changed

- UI readability pass: unified type scale, spacing rhythm, and control styling across Home, Logs, Analysis, Prune, and Login; visible keyboard-focus states; level conveyed by text as well as color (`ui-readability-pass`).

### Fixed

- The level selector no longer overlaps the neighbouring filter controls on Logs and Analysis; it is a single level row inside each filter card, wrapping cleanly across breakpoints (`fix-level-selector-layout`).

## 2026-10-06

### Added

- Clickable node and level selectors on the Analysis and Prune pages, matching the Logs page; clicking toggles multi-select scope on Analysis and selects the single-node scope on Prune (`analysis-prune-node-level-selectors`).
- Logs page: per-row copy action carrying the full record in the export's field order, and explicit resizable columns for timestamp, level, node, message, and source location (`improve-logs-page`).
- Logs shows the total number of rows matching the active filters; the Prune preview shows the matching-row count plus a bounded sample of newest rows before confirm; a Logs-to-Analysis handoff carries the active filters; Analysis honors the `search` keyword in every breakdown (`logs-prune-analysis-enhancements`).

## 2026-10-05

### Added

- Scheduled retention prune: unattended deletes of rows older than a configured age at a configured time of day, reusing the shared age vocabulary (`add-scheduled-retention-prune`).
- Background-task configuration persisted in CubDB: the retention policy edited on the Prune page survives application restarts and takes precedence over the env-seeded default; the compose stack gains a named volume and a store-directory variable (`persist-background-task-config`).

### Changed

- The Basic-auth browser challenge is replaced by a dedicated token page and session cookie; sessions record a digest of the token so rotating it invalidates outstanding sessions; a sign-out control is added to the shell **BREAKING:** `curl -u` / `Authorization: Bearer` workflows no longer authenticate (scripted clients log in once and carry the cookie) and unauthenticated browsers are redirected rather than 401-challenged (`replace-basic-auth-with-token-form`).

### Fixed

- A custom `CLICKHOUSE_USER` actually reaches ClickHouse: the dashboard URL gets percent-encoded userinfo and the compose healthcheck uses the same user (`fix-clickhouse-custom-username-auth`).
- `check_origin` accepts the documented loopback entry points (`localhost` / `127.0.0.1`, any port), so LiveView sockets connect instead of falling back to a longpoll reconnect loop (`fix-liveview-check-origin`).
- `podman compose up --build` from a clean checkout produces a working stack: a `build` section was added and both containers publish their literal matching ports (dashboard `5051`, ClickHouse `8124`/`9001`) with `CLICKHOUSE_DATABASE=cluster_log` pinned across `compose.yaml` / `.env.example` / `runtime.exs` (`fix-podman-compose`).

## 2026-10-03

### Changed

- Postgres is removed entirely — the dashboard reads only ClickHouse **BREAKING:** `LoggerDashboard.Repo`, the Ecto Postgres deps/config, and `DATABASE_URL` are gone; a `compose.yaml` stack (dashboard + ClickHouse) replaces them, with gitignored `.env` secrets provisioned fail-fast and ClickHouse DDL applied by `bin/migrate` at container start (`podman-compose-no-postgres`).

### Fixed

- The Analysis page now states only what it actually computed (`fix-analysis-result-presentation`):
  - the volume-over-time table renders every level series and names each one, instead of dropping all series but the first;
  - the bucket select shows the bucket actually applied instead of silently reverting the operator's choice on submit;
  - a rejected filter clears the previous results instead of leaving them beside the error;
  - per-node counts are ordered descending by count (they were alphabetical);
  - level counts are disclosed as computed over a bounded sample rather than presented as exact totals.

## 2026-10-02

### Added

- Initial MVP dashboard over the shared `logs` ClickHouse table: node-scoped log viewer with pagination, wildcard search, datetime range, and level filter; an Analysis page (level frequency, time-bucketed volume, per-node counts); and a Prune control with explicit confirmation of scope, range, and result counts (`logger-dashboard-mvp`).
- Real dashboard homepage and a persistent cross-page navigation shell; multi-node filtering on Logs and Analysis; polished UI of all pages (`improve-dashboard-ui-and-multi-node-filter`).
- First-party `Containerfile` and token access control in front of all routes: `DASHBOARD_AUTH_TOKEN` or an auto-generated ephemeral token printed at boot, plus `mix logger_dashboard.gen.token` (`add-containerfile-basic-auth`).
- A dev/demo seeder: `mix logger_dashboard.seed_logs` writes synthetic rows with levels, `--nodes` distribution, date-range spread, volume controls, presets, and `--dry-run` (`demo-data-generator`).

### Changed

- Log rows render as dense single lines — timestamp, level, node, message, source — with over-long messages truncated by ellipsis and the full text on hover or by expanding the row; per-page sizes are now 100/500/3000 with 3000 as the cap and 100 as the default **BREAKING** (replaces the two-line card and the 25/50/100 sizes); the current page exports as raw text (`add-dense-log-view-and-raw-export`).
- The shell widens (no more per-page width caps), rows gain a level accent plus metadata rendering, and a shared UTC datetime picker with server-resolved relative shortcuts arrives — `last 1 hour`, etc. on the viewer and age shortcuts on Prune (`widen-log-view-and-add-time-range-shortcuts`).
- All reads move onto raw SQL through `ClickhouseExLogger.Repo` so wildcard search is a database-evaluated `LIKE` with complete results, and pruning rejects both a missing explicit scope and an unbounded prune rather than defaulting to `DELETE WHERE 1 = 1` **BREAKING** (previously a regex over the newest 1,000 prefiltered rows silently truncated search results) (`raw-sql-log-reads`).

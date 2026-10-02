# Proposal

## Why

The log viewer wastes the screen it has. Every page is capped at
`max-w-6xl` (1152px) by the shared shell, and each log row is a stacked card
that spends three vertical lines to show one message — so a long message
wraps into the narrow column and the operator scrolls instead of scanning. At
the same time, the only way to express "what happened in the last ten minutes"
is to hand-type a UTC ISO8601 string into a plain text box, and the prune page
makes an operator retype a datetime to say "delete yesterday's logs" — on a
page where a mistake is irreversible.

## What Changes

- **Widen the shell.** Drop the `max-w-6xl` cap from `Layouts.app`'s header
  row and `<main>`, and drop the second `max-w-3xl` cap the Prune page adds
  inside the shell, so one container governs every page.
- **Render each log row as two lines instead of a card.** A compact header
  line carrying `node`, `timestamp` (UTC), and `level`, followed by the
  message and source location. The row carries a level-coloured accent so
  errors and warnings are scannable at a glance.
- **Render `metadata`.** The `log-viewing` spec has always required it in the
  row contents and the viewer has never shown it; restructuring the row is the
  moment to close that gap.
- **Add a UTC datetime picker.** `from`/`to` gain a native
  `datetime-local` picker beside the existing ISO8601 text field, showing and
  submitting UTC so the wire format stays strict ISO8601 UTC. No new
  dependency; a colocated JS hook keeps the two in sync.
- **Add relative-range shortcuts to the viewer**: last 10 minutes, 1 hour,
  6 hours, 24 hours, 7 days, and All time.
- **Add age shortcuts to the prune page**: older than 1 day, 3 days, 7 days,
  30 days, and 90 days, alongside a UTC datetime picker for its `from`/`to`.
- **Resolve shortcuts server-side.** A shortcut button pushes a `preset` param;
  the server resolves it to a concrete range at render time, so a bookmarked
  "last hour" URL is never stale. The relative window belongs to
  `Filter`, which already owns param parsing for the viewer, Analysis, and
  prune.
- **Share the picker and shortcut control** across Logs, Analysis, and Prune
  instead of growing a third divergent copy of the filter form.

### Non-goals

- No change to the SQL predicates, the raw read path, prune safety rules, or
  the ClickHouse schema. `Filter.predicates/1` still emits the same bound
  clause set in the same order.
- No new JavaScript dependency.
- No live/streaming log tail; the viewer stays paginated and pull-based.
- No multi-node pruning. `Prune.parse/1` continues to reject a multi-node
  value.

## Capabilities

### New Capabilities

- `time-range-input`: How an operator expresses a datetime range — a UTC
  `datetime-local` picker paired with the existing ISO8601 field, and
  server-resolved relative shortcuts for both lookback windows and prune
  age cutoffs.

### Modified Capabilities

- `log-viewing`: `Requirement: Node-scoped log listing` — the "Log row
  contents" scenario now also fixes the row's two-line shape (header: node,
  datetime, level; body: message and source) and its level-coloured accent.
- `dashboard-shell`: `Requirement: Consistent page shell` — the content
  container spans the viewport instead of capping at a fixed max width, and
  no page imposes a second width of its own.
- `log-pruning`: `Requirement: Scoped prune selection` gains the age-cutoff
  shortcuts, and `Requirement: Time-bounded prune by default` gains the
  invariant that a shortcut only fills the bound — it still cannot reach a
  delete without the existing preview-and-confirm step.

## Impact

- **Domain** — `LoggerDashboard.Logs.Filter` gains a `preset` field, a shared
  relative-duration vocabulary, and preset resolution; `parse/1` precedence
  gains one documented rule. `LoggerDashboard.Logs.Prune` routes its age
  shortcuts through the same resolution.
- **Web** — `LoggerDashboardWeb.Layouts` (width), `LogLive.Index` and
  `PruneLive.Index` (forms, shortcuts, row markup),
  `AnalysisLive.Index` (same filter controls). One new shared UI module for
  the picker/shortcut control, imported in `logger_dashboard_web.ex`.
- **JS/CSS** — one colocated hook syncing picker ↔ text field; Tailwind classes
  for the row accent and shortcut buttons. No `assets/package.json` change.
- **Tests** — `filter_test.exs` gains preset-resolution cases;
  `log_live_test.exs` and `prune_live_test.exs` gain shortcut and row-structure
  assertions. Existing assertions on `#logs-filter-form`, `#logs-list`,
  `#logs-pagination`, `#logs-active-nodes`, `#prune-form`, and the
  `prune_node` label wording are preserved.
- **Compatibility** — the URL contract is unchanged. Existing
  `/logs?from=...&to=...` links keep working; `preset` is additive.

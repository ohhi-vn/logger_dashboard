# Proposal

## Why

The Analysis page's **By node** panel is the heaviest thing on the page. It is a
full-width card that sits *below* the other two breakdowns, so it reads as the
page's main event even though it carries no more information than the two
panels above it. Its chart scales with the page width, and its table can run to
a thousand rows — so the panel's size is decided by how many nodes happen to be
in scope, not by what the operator is trying to read. The **Volume over time**
table has the same problem in a different form: an hour bucket over a week is
168 rows, which makes the page taller than the fold many times over.

Around that sit three smaller rough edges. The active node scope is stated
twice — once in a "Nodes:" summary row and again by the pressed state of the
node badges immediately below it. The filter card leaves a half-empty row
because the Bucket select sits alone in a two-column cell under a full-width
level row. And the chart-style buttons are labelled with raw atoms (`bar`,
`donut`, `area`) rather than with names an operator would read.

## What Changes

- **One responsive grid for the three breakdowns.** By level, By node and Volume
  over time move into a single grid. On a wide viewport the two frequency
  breakdowns sit in narrow columns side by side and the time series takes the
  wider half; on a medium viewport the two frequency breakdowns sit side by side
  with the time series beneath them; on a narrow viewport all three stack. By
  node is never full-width again.
- **Result tables are compact and bounded.** All three result tables move
  together to the shell's compact table density, so they keep matching each
  other, and each sits in a bounded region that scrolls with its header row
  staying visible. A thousand-node breakdown and a 168-bucket volume breakdown
  stop setting the height of the page.
- **Chart heights are capped.** Each breakdown's chart draws in a fixed-height
  frame rather than scaling with its column, so the cards line up and a narrow
  By node column gets a small chart rather than a wide, shallow one.
- **The node scope is stated once.** The node scope control offers the known
  node values *and* every node in the active scope, so the scope is always
  visible and always removable through the badges. The Analysis page's
  duplicate "Nodes:" summary row is removed.
- **Chart-style buttons name their style.** `bar` / `pie` / `donut` / `line` /
  `area` become `Bar` / `Pie` / `Donut` / `Line` / `Area` in the button face.
  The URL param and the control's element ids are unchanged, so existing links
  and the existing tests keep working.
- **The filter card has no half-empty row.** The Bucket select moves up into
  the first row beside the range inputs, so the card's rows are fully occupied
  and the level row keeps its own full-width row.
- **The limit disclosure is trimmed** to the one sentence an operator needs:
  how many rows the numbers were computed over.

**This change alters no counts, no filters, no URL params and no query.** It is
presentation only: the numbers a breakdown reports are the same before and
after, and the same scope produces the same result.

## Capabilities

### New Capabilities

- None. This change reworks the presentation of the existing Analysis page
  within the current capability boundaries.

### Modified Capabilities

- `log-analysis`: the layout of the three breakdowns on the page (one
  responsive grid, with By node no longer full-width), the density and bounded
  height of the result tables, the bounded height of the breakdown charts, the
  removal of the duplicate active-node summary row, the wording of the
  chart-style control, and the tighter filter card.
- `log-filter-controls`: the node scope control offers every node in the
  active scope in addition to the known node values, so an active node is
  always visible and removable through the control.
- `log-viewing`: the same node-option guarantee, seen from the viewer — the
  known-node options are offered together with the active scope, with an
  active node that the table no longer holds offered ahead of them.

## Impact

- Affected code: `lib/logger_dashboard_web/live/analysis_live/index.ex` (the
  template, the `result_table` and `chart_style` private components, and the
  chart config the page hands to Chart.js),
  `lib/logger_dashboard_web/components/filter_controls.ex` (the node scope
  control's option set), `lib/logger_dashboard/logs/analysis.ex` (a label
  mapping for the chart styles it already owns), and
  `test/logger_dashboard_web/live/analysis_live_test.exs`.
- No change to `LoggerDashboard.Logs.Filter`, `LoggerDashboard.Logs.LogRead` or
  the analysis queries: the filters, the raw read path and the numbers are
  untouched. The shared node-scope control's *options* grow to include the
  active scope; its behaviour, its ids and its events do not change, so the
  Logs and Prune pages keep working and gain the same guarantee.
- No data-layer, DDL, dependency or configuration change. The chart config
  gains a `maintainAspectRatio` option and the canvas moves into a
  fixed-height frame; the data the chart draws is identical.
- Risk: the chart is created by a colocated hook on a `phx-update="ignore"`
  canvas, and the new fixed-height frame changes the element the canvas is
  measured against. The chart config continues to travel in the `data-chart`
  attribute, which LiveView still synchronises on an ignored element, so the
  chart keeps re-rendering when the scope or the style changes — but this must
  be verified in a browser, not only in a LiveView test.
- Verification note: `mix precommit` runs the `:clickhouse`-tagged tests, which
  need a running ClickHouse. A container must be up before the suite is run.

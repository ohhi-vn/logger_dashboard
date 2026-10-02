# Proposal

## Why

The log viewer spends most of its vertical space on chrome rather than log
content. Each entry renders as a two-line card with a header row, a message
row, a source-location row, and a metadata disclosure, separated by a visible
gap and per-row padding. At the default 50 rows per page an operator scanning an
incident sees far less log text than the viewport can hold, and the layout is
already dense enough that a single log line wraps to three or four rendered
lines, so the two-line card buys little.

Two gaps follow from that. The page-size control offers only 25, 50, and 100,
which is too coarse both for a quick skim and for pulling a wide window of
history in one go. And there is no way to take the rows currently on screen out
of the dashboard, so reviewing an incident window means screenshotting the page
or re-deriving the same query by hand elsewhere.

## What Changes

- **BREAKING** Render each log row as a single line carrying timestamp, level,
  node, message, and source location, replacing the current two-line card with
  separate header and body rows. This replaces the standing requirement that a
  long message is shown in full by wrapping.
- Truncate an over-long message on a single line with an ellipsis, and restore
  the full text on demand: the untruncated message is available on hover and by
  expanding that one row.
- **BREAKING** Offer 100, 500, and 3000 as the per-page row counts, replacing
  25, 50, and 100, and make 100 the default when the URL carries no explicit
  page size. This raises the largest accepted page size, so a `limit` above 3000
  is capped at 3000 rather than 500. A `limit` that reads as a positive whole
  number but is no longer offered is still honoured, so existing links keep
  working.
- Reduce the vertical padding within and between log rows so more log text fits
  in the viewport at the same page size.
- Add an export of the current page as raw text, covering exactly the rows on
  screen under the filters and page position currently in effect.
- Keep metadata reachable. A row carrying a non-empty metadata map remains
  expandable, and the expanded view shows the full untruncated message alongside
  it.

## Capabilities

### New Capabilities

None. Every behavior here belongs to the existing viewer; none warrants a
capability of its own.

### Modified Capabilities

- `log-viewing`: "Node-scoped log listing" changes to require a single-line
  row and to permit truncation of an over-long message, replacing the
  no-truncation scenario. "Paginated newest-first browsing" changes to fix the
  offered page sizes at 100, 500, and 3000 with 100 as the default. A new
  requirement, "Export the current page as raw text", covers the download.

## Impact

- `LoggerDashboardWeb.LogLive.Index` — row markup and spacing, the per-page
  select and its offered values, the pagination summary text, and a new export
  event that streams a file response to the client. No new route is needed;
  the download is served from the live view.
- `LoggerDashboard.Logs.Filter` — the default and maximum page-size constants.
  Clamping behavior is otherwise unchanged, so the old page sizes of 25 and 50
  remain accepted from an existing URL even though the control no longer offers
  them.
- `LoggerDashboard.Logs.LogRead` — read-only reuse. The export renders rows
  already fetched for the page rather than issuing a second query, so the
  read path and its raw-SQL predicate building are unchanged.
- `log_live_test.exs` — the row-shape and pagination suites assert the old
  two-line structure and the old page sizes, so they need rewriting; the
  ClickHouse-backed suites still require a running ClickHouse.
- No new dependencies, no schema or DDL change, and no other page is affected.

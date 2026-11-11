# Proposal

## Why

The Logs page can already review and export the rows it shows, but two gaps
slow operators down during an incident: there is no way to act on the rows a
filter selects without leaving the page for the full Prune flow, and the
export is a lossy, space-joined text line that drops metadata and is hard to
load into a spreadsheet. Operators also cannot take only the rows they care
about out of a page — the export always covers the whole page.

## What Changes

- **Short prune from the Logs page.** A destructive action on the Logs page
  prunes the rows matching the current filter set through a compact, in-page
  confirmation that reuses the existing prune review (count, per-node split,
  sample) and the same validated predicates. The full `/prune` page and its
  safety rules still govern; nothing deletes on GET or without an explicit
  confirm.
- **Row selection on the current page.** Each row gains a selection control;
  a select-all covers the page. Selection is page-local and never changes
  filters, page position, or rows shown.
- **Export becomes CSV with headers.** The page export writes a CSV file whose
  first row is the column names, carrying timestamp, level, node, message,
  module, function, file, line, and metadata for every exported row, with
  proper CSV quoting. When rows are selected, the export covers the selected
  rows; otherwise it covers all rows on the current page. The per-row copy
  action keeps its existing plain-text line format.
- **BREAKING** The exported file changes from `logs-export.txt` plain text to
  `logs-export.csv`, and its body changes from space-joined lines to CSV.
  Consumers parsing the old text format must switch to CSV.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `log-viewing`: adds short-prune action, row selection, and replaces the
  plain-text page export with a CSV export carrying metadata and source
  location.
- `log-pruning`: a prune may be initiated from the Logs page using the
  viewer's current filter, subject to the same scope, bounds, review, and
  confirmation rules.

## Impact

- `LoggerDashboardWeb.LogLive.Index` — new selection state, short-prune
  confirmation panel, and CSV export event.
- `LoggerDashboard.Logs.LogLine` — CSV rendering helpers alongside the
  existing text line.
- `LoggerDashboard.Logs.Prune` — reused by the short-prune path; no new
  delete semantics.
- `log_live_test.exs` and `log_line_test.exs` — export and prune
  assertions updated to CSV and selection.
- No DDL or upstream change; ClickHouse remains the only data store.

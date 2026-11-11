# Design

## Context

The Logs LiveView (`LoggerDashboardWeb.LogLive.Index`) already fetches a page
of rows into `@page_rows`, exports them via `LogLine.format_page/1`, and
delegates pruning to `LoggerDashboard.Logs.Prune`. The export path pushes a
`logs-download` event to the client with a body string, filename, and content
type. `LogLine` owns the field order and escaping used by both the row and
the export.

## Goals / Non-Goals

**Goals:**
- Add CSV rendering to `LogLine` without losing the existing plain-text line
  used by copy-row.
- Add page-local row selection to the LiveView and use it to narrow the export.
- Add an in-page short-prune flow that reuses `Prune.parse/1`, `Prune.review/1`,
  and `Prune.run/2` rather than duplicating delete logic.
- Keep all SQL parameterized and the read path unchanged.

**Non-Goals:**
- No change to `LogRead` queries or pagination.
- No new route; short prune lives inside `/logs`.
- No per-row prune; short prune targets the whole current filter set.
- No spreadsheet-style formatting beyond CSV quoting.

## Decisions

### Export format: CSV with a header row

`LogLine` gains `csv_header/0` and `csv_row/1` (plus `csv_page/2` for a list).
The header is the fixed column list `timestamp, level, node, message, module,
function, file, line, metadata`. Each cell is rendered through an RFC 4180
quoter: fields containing a comma, quote, CR, or LF are wrapped in double
quotes and embedded quotes doubled. `message` is carried raw (not escape-
sequenced), so multi-line messages become quoted multi-line cells rather than
`\n` sequences; `metadata` is serialized as JSON via `Jason` (or `inspect/1`
as fallback) and quoted. The filename becomes `logs-export.txt` →
`logs-export.csv` and the content type `text/csv; charset=utf-8`.

Alternative considered: keep `\n` escaping inside CSV. Rejected because CSV
already has a quoting mechanism for newlines, and escaping would make the
message differ from the stored value.

### Selection state

Add `@selected_ids :: MapSet.t()` to the LiveView assigns, reset to empty in
`apply_filter_params/2` (so a new filter or page clears stale selections) and
on mount. The template renders a checkbox per row keyed by the row's dom id;
a header checkbox toggles all rows on the current page. Export uses
`selected_rows = Enum.filter(page_rows, &MapSet.member?(selected_ids, row_dom_id(&1)))`;
if non-empty, export those, otherwise all `page_rows`. The selection set is
never sent to the server as a filter; it is pure UI state.

### Short prune: reuse the Prune module

The Logs page constructs a prune params map from the current filter:
`%{"scope" => scope, "node" => node, "from" => ..., "to" => ..., "level" => ...,
"preset" => filter.preset}` where `scope` is `"node"` when exactly one node is
selected and `"all"` otherwise (multi-node or none). It calls `Prune.parse/1`;
on success it calls `Prune.review/1` to obtain count, per-node distribution,
and sample, and stores them in `@prune_review`. Confirm calls `Prune.run/2`.
The review panel is rendered inline (not a modal) and is cleared whenever the
filter changes. An invalid or unbounded filter surfaces the parse error in
the panel and disables confirm.

Alternative considered: navigate to `/prune` with the filter (a handoff like
Analyze). Rejected because "short prune" implies staying on the page; the
in-page review reuses the same data, so no second query model is introduced.

### Breaking change to filename

The old `@export_filename "logs-export.txt"` becomes `"logs-export.csv"`. The
client download hook already takes filename and content type from the event
payload, so no JS change is required.

## Risks / Trade-offs

- [Short prune on multi-node filter widens scope to all nodes] → The review
  panel states the resolved scope explicitly, and the count/per-node split
  makes the widening visible before confirm.
- [CSV quoting bugs could corrupt exports] → Centralize quoting in one helper
  with unit tests covering commas, quotes, and newlines.
- [Selection state lost on re-render] → Selection is an assign, not derived
  from the stream, and is reset only on filter/page change by design.
- [Metadata serialization cost on 3000-row pages] → Metadata is already
  loaded; JSON encoding per row is O(n) and acceptable for the page sizes
  offered.

## Migration Plan

1. Add CSV helpers to `LogLine` and tests.
2. Add selection assigns and checkboxes; update export event.
3. Add short-prune review state and handlers; render panel.
4. Update existing tests for filename/content type and CSV body.

Rollback: revert the change; the old text export is restored by reverting
`LogLine` and the LiveView event. No data migration is involved.

## Open Questions

None.

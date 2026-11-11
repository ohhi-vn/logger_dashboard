# Spec Delta

## REMOVED Requirements

### Requirement: Export the current page as raw text

**Reason**: The page export is replaced by a CSV export that carries metadata
and source location in named columns, so the old space-joined plain-text format
is no longer produced.

**Migration**: Consumers of `logs-export.txt` switch to `logs-export.csv`,
which carries a header row and one CSV row per exported log.

## ADDED Requirements

### Requirement: Select rows on the current page for export

The system SHALL offer a selection control on every row of the current page,
plus a select-all control for the page. Selection SHALL be page-local: it
SHALL NOT change the page's filters, page position, or rows shown, and it
SHALL reset when the page's rows change.

#### Scenario: Selecting a row marks it

- **WHEN** user toggles the selection control on a row
- **THEN** that row is marked selected and its selection state is visible

#### Scenario: Select-all toggles every row on the page

- **WHEN** user triggers select-all on the current page
- **THEN** every row on the page becomes selected, and triggering it again
  clears every selection

#### Scenario: Selection does not disturb the page

- **WHEN** user selects or clears rows
- **THEN** the page's filters, page position, and rows shown are unchanged

#### Scenario: Selection resets on a new page

- **WHEN** the page's rows change because of a filter or page change
- **THEN** no row from the previous page remains selected

### Requirement: Export the current page as CSV

The system SHALL offer an export of the rows on the current page as a CSV
file the browser downloads. When one or more rows are selected, the export
SHALL cover only the selected rows; otherwise it SHALL cover all rows on the
current page. The export SHALL honour the current filters and page position,
and SHALL NOT widen the scope to other pages or to the whole filtered result
set.

The file SHALL be named `logs-export.csv`, served as `text/csv`, and its
first row SHALL be a header row naming the columns in order: `timestamp`,
`level`, `node`, `message`, `module`, `function`, `file`, `line`,
`metadata`. Each following row SHALL carry those fields for one log, with
`node` rendered as the explicit placeholder `unknown` when the row has no
node, and `metadata` serialized as a JSON object (or empty when there is
none). Values SHALL be quoted per CSV rules so commas, quotes, and newlines
in a message or metadata value cannot break a record's columns.

Rows SHALL be ordered newest-first by `timestamp`, matching the page. Exporting
SHALL NOT change the page's filters, page position, or rows shown.

#### Scenario: Exporting downloads a CSV file

- **WHEN** user triggers the export
- **THEN** the browser downloads `logs-export.csv` with content type
  `text/csv` and a header row as the first line

#### Scenario: The export covers selected rows when any are selected

- **WHEN** user exports while one or more rows are selected
- **THEN** the file contains exactly those selected rows and no others

#### Scenario: The export covers the whole page when none are selected

- **WHEN** user exports while no row is selected
- **THEN** the file contains exactly the rows shown on the current page

#### Scenario: The export honours the active filters and page position

- **WHEN** user exports from a page that is not the first page while filters
  are active
- **THEN** the file contains only rows matching those filters on that page

#### Scenario: Each row carries metadata and node name

- **WHEN** user exports a page containing a row with metadata and a node
- **THEN** that row's CSV record carries the node name and the metadata value

#### Scenario: A row with no node exports the placeholder

- **WHEN** an exported row has no `node`
- **THEN** that row's `node` column reads `unknown`

#### Scenario: A multi-line message stays in one record

- **WHEN** an exported row's message contains newlines
- **THEN** the message's newlines are contained within that record's quoted
  field and the following record's columns are not interleaved

#### Scenario: Exporting preserves newest-first order

- **WHEN** user exports a page
- **THEN** the records appear in the same newest-first order as the rows on
  the page

#### Scenario: Exporting does not disturb the page

- **WHEN** user triggers the export
- **THEN** the page's filters, page position, and rows shown are unchanged

#### Scenario: Exporting an empty selection on an empty page yields a header only

- **WHEN** user exports a page showing no rows
- **THEN** the download succeeds and the file contains the header row and no
  data rows

### Requirement: Short prune from the Logs page

The system SHALL offer a short-prune action on the Logs page that deletes the
rows matching the current filter set. It SHALL reuse the existing prune review
and validated predicates: it SHALL show the matching-row count, the per-node
distribution, and a bounded sample of the newest matching rows, and it SHALL
require an explicit confirmation before any delete runs. It SHALL be available
only when the current filter is valid and bounded according to the prune
safety rules; otherwise it SHALL report the validation error and run no
delete. Deleting SHALL NOT happen on GET or without confirmation, and the
page's filters, position, and rows SHALL remain unchanged until a confirmed
delete completes, after which the page SHALL refresh.

#### Scenario: Short prune shows a review before deleting

- **WHEN** user triggers short prune with a valid bounded filter
- **THEN** the page shows the matching-row count, per-node distribution, and
  a sample of the newest matching rows, and offers a confirm action

#### Scenario: Confirming short prune deletes the matching rows

- **WHEN** user confirms the short-prune review
- **THEN** the system deletes the rows matching the current filter and
  refreshes the page

#### Scenario: Cancelling short prune deletes nothing

- **WHEN** user cancels the short-prune review
- **THEN** the system deletes zero rows

#### Scenario: An unbounded filter blocks short prune

- **WHEN** user triggers short prune with neither a from nor a to bound and
  no explicit all-time mark
- **THEN** the system rejects it with a validation error and runs no delete

#### Scenario: A rejected filter blocks short prune

- **WHEN** user triggers short prune while the current filter is rejected
- **THEN** the system reports the validation error and runs no delete

#### Scenario: Short prune does not disturb the page before confirmation

- **WHEN** user opens the short-prune review
- **THEN** the page's filters, page position, and rows shown are unchanged

## MODIFIED Requirements

### Requirement: Copy log row as text

The system SHALL offer a per-row action that copies that row's full record as
text, carrying the UTC `timestamp`, the `level`, the `node` (or the explicit
placeholder for a row with no node), the untruncated `message`, and the
source location when the row has one. The copied text SHALL use the
plain-text line format with the same field order and escaping as before, and
copying SHALL NOT change the page's filters, its page position, or the rows
shown.

#### Scenario: Copying a row copies its full info

- **WHEN** user triggers the copy action on a row
- **THEN** the clipboard receives that row's UTC `timestamp`, `level`,
  `node`, untruncated `message`, and source location when present

#### Scenario: Copying a node-less row uses the placeholder

- **WHEN** user copies a row whose `node` is absent
- **THEN** the copied text carries the explicit node placeholder rather than
  an empty field

#### Scenario: Copying carries the untruncated message

- **WHEN** user copies a row whose message is shortened on the row
- **THEN** the copied text carries the full untruncated message

#### Scenario: Copying does not disturb the page

- **WHEN** user copies a row
- **THEN** the page's filters, its page position, and the rows shown are
  unchanged

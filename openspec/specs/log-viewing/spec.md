# Log Viewing Specification

## Purpose

Lets operators browse logs shipped by `clickhouse_ex_logger` from a single place, scoped to one or more nodes or all nodes with fast time-pruned filtering.

## Requirements

### Requirement: Node-scoped log listing

The system SHALL list log rows from the shared `logs` table scoped to zero, one, or more selected nodes, defaulting to newest-first by `timestamp`. A scope with no selected node SHALL include every node, including rows where `node` is NULL. A scope with one or more selected nodes SHALL match rows whose `node` equals any selected value.

Each row SHALL be rendered as a single line rather than as a stacked card, carrying the UTC `timestamp`, `level`, `node`, `message`, and the available source location on that one line. The row SHALL carry a visual accent keyed to its level so that `error` and `warning` rows are distinguishable while scanning. Level SHALL remain readable as text and SHALL NOT be conveyed by color alone. The list SHALL present explicit columns for `timestamp`, `level`, `node`, `message`, and source location, and the columns SHALL be resizable by the user without changing the rows, filters, or page position.

A row SHALL NOT exceed a single line's height. A `message` too long to fit within the available width SHALL be shortened with a trailing ellipsis on the row, and the untruncated message SHALL remain reachable: it is exposed on hover and shown in full when that row is expanded. Nothing in the shortening SHALL be discarded from the system, and the export of that page SHALL carry the untruncated message. Expanding a row SHALL reveal the full `message` and, when the row carries them, its `metadata`; it SHALL NOT change the page's filters, its page position, or the rows on the page.

Spacing between and within rows SHALL be tight enough that the rows in a page are legible as a continuous list rather than as separated cards. Filter badges, inputs, and actions SHALL use the shell's shared visual language, and every badge and row action SHALL show a visible keyboard-focus indicator and remain operable by keyboard. Validation errors SHALL name the rejected field in text and SHALL NOT rely on color alone.

#### Scenario: View logs for a node

- **WHEN** user selects node `my_app@10.0.0.5`
- **THEN** system shows only rows where `node` equals that value ordered by
  `timestamp` descending

#### Scenario: View logs for multiple nodes

- **WHEN** user selects nodes `my_app@10.0.0.5` and `my_app@10.0.0.6`
- **THEN** system shows rows where `node` equals either selected value, ordered
  by `timestamp` descending

#### Scenario: View logs for whole system

- **WHEN** user selects no node
- **THEN** system shows rows from all nodes including rows where `node` is
  NULL, ordered by `timestamp` descending

#### Scenario: Node values are bound, not interpolated

- **WHEN** user supplies one or more node values
- **THEN** system matches them with bound parameters and no node text reaches
  the SQL string

#### Scenario: Log row contents

- **WHEN** a log row is rendered
- **THEN** system shows `timestamp` (UTC), `level`, `node`, `message`, and
  available `module`/`function`/`file`/`line`/`metadata`

#### Scenario: A row occupies a single line

- **WHEN** a log row is rendered
- **THEN** its `timestamp`, `level`, `node`, `message`, and available source
  location all appear on one line, and the row is no taller than one line

#### Scenario: An over-long message is shortened on the row

- **WHEN** a row's `message` is longer than the available width
- **THEN** the row shows the message shortened with a trailing ellipsis, does
  not grow taller than one line, and does not wrap

#### Scenario: The full message is available on hover

- **WHEN** a row's message has been shortened
- **THEN** the untruncated message is exposed for that row on hover

#### Scenario: Expanding a row shows the full message

- **WHEN** user expands a row
- **THEN** the full untruncated `message` is shown for that row

#### Scenario: Expanding a row shows its metadata

- **WHEN** user expands a row that carries a non-empty `metadata` map
- **THEN** system shows that metadata alongside the full message

#### Scenario: Expanding a row leaves the page otherwise unchanged

- **WHEN** user expands a row
- **THEN** the page's filters, its page position, and the rows shown are
  unchanged

#### Scenario: A row with no metadata expands to its message alone

- **WHEN** user expands a row whose `metadata` is empty
- **THEN** the full message is shown and no empty metadata section is offered

#### Scenario: Non-empty metadata is shown

- **WHEN** a log row carries a non-empty `metadata` map
- **THEN** system shows that metadata with the row once the row is expanded

#### Scenario: Level is distinguishable by accent and readable as text

- **WHEN** rows of differing levels are shown together
- **THEN** each row's accent corresponds to its level and the level remains
  present as text

#### Scenario: Rows read as a continuous list

- **WHEN** a page shows several rows
- **THEN** the spacing within and between the rows is tight enough that the
  page reads as a continuous list of log lines rather than as separated cards

#### Scenario: Columns are explicit

- **WHEN** a page shows log rows
- **THEN** each row exposes distinct `timestamp`, `level`, `node`, `message`, and source-location columns in a consistent order

#### Scenario: Columns are resizable

- **WHEN** user resizes a column
- **THEN** that column's width changes while the rows, filters, and page position stay unchanged

#### Scenario: Expanding a row does not disturb column widths

- **WHEN** user expands a row after resizing columns
- **THEN** the chosen column widths are preserved

#### Scenario: Filter controls match the shared visual language

- **WHEN** user views the Logs page filter badges, inputs, and actions
- **THEN** they use the shell's shared styling for the same elements, so a
  control learned on another page is recognizable here

#### Scenario: Row and badge actions are keyboard operable with visible focus

- **WHEN** user tabs through level badges, node options, and row actions
- **THEN** each focused control shows a visible focus indicator and activates
  from the keyboard

#### Scenario: Filter errors name the field in text

- **WHEN** user submits a filter the system rejects
- **THEN** the error names the rejected field in text rather than relying on
  color alone

### Requirement: Wildcard text search

The system SHALL support wildcard text search over `message` (e.g. `*timeout*`, `db_*`) translated to a ClickHouse `LIKE`/`match` predicate. The predicate SHALL be evaluated by the database against every row in the active scope, not applied in application memory to a bounded subset.

#### Scenario: Wildcard search filters rows

- **WHEN** user enters `*timeout*` in search
- **THEN** system returns only rows whose `message` matches the wildcard pattern

#### Scenario: Empty search returns unfiltered messages

- **WHEN** search text is empty
- **THEN** system applies no message predicate

#### Scenario: Search matches beyond the most recent rows

- **WHEN** matching rows exist that are not among the most recent rows in the active scope
- **THEN** system still returns those matches, and returns them in the same pagination sequence as unsearched rows

#### Scenario: Search combines with other active filters

- **WHEN** user enters a search pattern together with a node scope, datetime range, and level
- **THEN** system applies the message pattern only to rows already matching that scope, range, and level

### Requirement: Datetime-range filter

The system SHALL filter by an explicit UTC datetime range on `timestamp` with inclusive bounds.

#### Scenario: Filter by datetime range

- **WHEN** user sets `from=2026-09-01T00:00:00Z` and `to=2026-09-02T00:00:00Z`
- **THEN** system returns only rows where `timestamp` is within that range

#### Scenario: Invalid range rejected

- **WHEN** user submits `from` after `to` or unparseable datetimes
- **THEN** system rejects the filter with a validation error and runs no query

### Requirement: Level filter

The system SHALL filter by zero, one, or more log levels from `error`, `warning`, `info`, `debug`. It SHALL present each level as a clickable toggle option plus an `all` reset option, and clicking a level option SHALL toggle that level in or out of the active level set without disturbing the other active filters. An empty level set, or selecting `all`, SHALL apply no level predicate. A non-empty level set SHALL match rows whose `level` equals any selected value. The `level` URL param SHALL accept a comma-separated list (e.g. `level=error,warning`); a single value, `all`, absent, or blank SHALL keep working as a one-element or empty set. An unknown level value SHALL reject the filter with a validation error and run no query. Level values SHALL be matched with bound parameters and no level text reaches the SQL string.

#### Scenario: Filter by single level

- **WHEN** user selects level `error`
- **THEN** system returns only rows where `level` equals `error`

#### Scenario: Filter by multiple levels

- **WHEN** user selects levels `error` and `warning`
- **THEN** system returns only rows where `level` equals `error` or `warning`, ordered by `timestamp` descending

#### Scenario: All levels

- **WHEN** user selects `all` or selects no level
- **THEN** system applies no level predicate

#### Scenario: Clicking a level selects it

- **WHEN** user clicks the `warning` level option
- **THEN** system shows only rows where `level` equals `warning` and marks `warning` as the active level

#### Scenario: Clicking levels replaces the previous level

- **WHEN** user clicks level `info` while level `error` is active
- **THEN** system shows rows where `level` equals `error` or `info` (clicking adds to the set rather than replacing it)

#### Scenario: Clicking an unselected level adds it

- **WHEN** user clicks the `warning` level option while `error` is active
- **THEN** system shows rows where `level` equals `error` or `warning` and marks both as active

#### Scenario: Clicking a selected level removes it

- **WHEN** user clicks the `error` level option while `error` and `warning` are active
- **THEN** system shows only rows where `level` equals `warning`

#### Scenario: Removing the last level returns to all levels

- **WHEN** user clicks the only active level option
- **THEN** system applies no level predicate and marks `all` as active

#### Scenario: Clicking all clears the level filter

- **WHEN** user clicks the `all` level option while one or more levels are active
- **THEN** system applies no level predicate and marks `all` as active

#### Scenario: Single-level bookmark keeps working

- **WHEN** user opens `?level=error`
- **THEN** system applies a one-element `error` set and marks `error` as active

#### Scenario: Invalid level rejected

- **WHEN** user submits `level=verbose` or `level=error,bogus`
- **THEN** system rejects the filter with a validation error and runs no query

#### Scenario: Level values are bound, not interpolated

- **WHEN** user supplies one or more level values
- **THEN** system matches them with bound parameters and no level text reaches the SQL string

#### Scenario: Level combines with other active filters

- **WHEN** user selects levels `error,warning` together with a node scope, datetime range, and search pattern
- **THEN** system applies the level set only to rows already matching that scope, range, and pattern

### Requirement: Paginated newest-first browsing

The system SHALL paginate log results with limit/offset and preserve active filters across pages. Pages SHALL be drawn from the complete set of rows matching the active filters.

The per-page row count SHALL be selectable from 100, 500, and 3000, and 100 SHALL be used when no page size is specified. A page SHALL hold at most 3000 rows.

A page size carried in the URL that reads as a positive whole number SHALL be honoured, so a page size that is no longer offered but still reachable by an existing link keeps working. A page size above 3000 SHALL be capped at 3000. A page size that does not read as a positive whole number SHALL fall back to 100 rather than being rejected.

Whether further pages exist SHALL be determined from the rows actually matching the active filters, not inferred from the current page being full. A page holding exactly the per-page row count SHALL report that no further pages exist when no further rows match. The rows used to determine this SHALL NOT be shown on the page, so a page holds at most the selected number of rows and an export of that page contains exactly the rows displayed.

The system SHALL show the total number of rows matching the active filters (node, search, datetime-range, level) alongside the pagination controls. The total SHALL be computed from the same predicates as the page rows, SHALL update whenever any active filter changes, and SHALL read zero when no rows match. A filter the system rejects SHALL show no total rather than a stale total from a previous request.

#### Scenario: Paginate filtered logs

- **WHEN** user advances to the next page with filters active
- **THEN** system keeps node, search, datetime-range, and level filters and shows
  the next slice in `timestamp` descending order

#### Scenario: Empty result

- **WHEN** no rows match the active filters
- **THEN** system shows an empty state naming the active scope/filters

#### Scenario: Last page signals end of results

- **WHEN** a page returns fewer rows than the per-page limit
- **THEN** system indicates that no further pages exist and offers no way to
  advance past the last page

#### Scenario: A full page at the end of results signals no further pages

- **WHEN** a page holds exactly the per-page row count and no further rows match the
  active filters
- **THEN** system indicates that no further pages exist and offers no way to advance

#### Scenario: A full page with more rows behind it offers a next page

- **WHEN** a page holds exactly the per-page row count and further rows match the
  active filters
- **THEN** system offers a way to advance to those further rows

#### Scenario: The row used to detect further pages is not shown

- **WHEN** the system determines that further pages exist
- **THEN** the page still holds at most the selected number of rows

#### Scenario: Page size and scope are preserved when advancing

- **WHEN** user advances from a page and the active filters are unchanged
- **THEN** system keeps the per-page size and the active scope in the resulting
  page

#### Scenario: The offered page sizes are 100, 500, and 3000

- **WHEN** user views the per-page row count control
- **THEN** it offers exactly the choices 100, 500, and 3000

#### Scenario: The default page size is 100

- **WHEN** user opens the viewer with no page size specified
- **THEN** the page shows at most 100 rows and the control shows 100 as the
  active page size

#### Scenario: Selecting a page size shows that many rows

- **WHEN** user selects 500 as the per-page row count
- **THEN** the page shows at most 500 rows, and the same size stays in effect
  while advancing to the next page

#### Scenario: A page size outside the offered set is still honoured

- **WHEN** a URL carries a per-page row count that reads as a positive whole
  number but is not one of 100, 500, or 3000
- **THEN** system uses that page size rather than rejecting the request

#### Scenario: A page size above the maximum is capped

- **WHEN** a URL carries a per-page row count greater than 3000
- **THEN** the page holds at most 3000 rows

#### Scenario: An unreadable page size falls back to the default

- **WHEN** a URL carries a per-page row count that is not a positive whole
  number
- **THEN** system uses 100 and reports no error

#### Scenario: Total reflects the active filters

- **WHEN** user views the Logs page with node, search, datetime-range, and level filters active
- **THEN** system shows the count of all rows matching those filters, not just the rows on the current page

#### Scenario: Total updates with filters

- **WHEN** user changes any active filter and the page reloads
- **THEN** the shown total matches the new filter set

#### Scenario: Empty scope shows zero total

- **WHEN** no rows match the active filters
- **THEN** system shows a total of zero alongside the empty state

#### Scenario: Rejected filter shows no total

- **WHEN** user submits a filter the system rejects
- **THEN** system shows the validation error and no total from a previous request

### Requirement: Multi-value node input

The system SHALL accept a node filter containing one or more node names separated by commas. It SHALL trim surrounding whitespace from each entry, ignore blank entries, and treat an input that reduces to no entries as "all nodes". It SHALL display the active node scope on the page and provide a single action that clears the node filter back to all nodes. It SHALL additionally present the known nodes as clickable options alongside the text input, and clicking an option SHALL toggle that node in or out of the active scope without disturbing the other active filters.

#### Scenario: Comma-separated nodes parse to a set

- **WHEN** user enters `my_app@10.0.0.5, my_app@10.0.0.6`
- **THEN** system filters by both nodes

#### Scenario: Whitespace and blank entries ignored

- **WHEN** user enters `my_app@10.0.0.5, , my_app@10.0.0.6,`
- **THEN** system filters by the two non-blank nodes

#### Scenario: Blank input means all nodes

- **WHEN** user submits a node filter that is empty or only commas/whitespace
- **THEN** system applies no node predicate

#### Scenario: Active node scope is visible and clearable

- **WHEN** a node filter is active
- **THEN** system shows the selected nodes on the page and offers a clear action that returns to all nodes

#### Scenario: Clicking an unselected node adds it to the scope

- **WHEN** user clicks a node option that is not in the active scope
- **THEN** system adds that node to the scope and refreshes the rows while keeping search, datetime-range, level, and pagination position semantics for the new scope

#### Scenario: Clicking a selected node removes it from the scope

- **WHEN** user clicks a node option that is already in the active scope
- **THEN** system removes that node from the scope, and removing the last selected node returns to all nodes

#### Scenario: Clicking nodes preserves other filters

- **WHEN** user toggles a node option while search, datetime-range, or level filters are active
- **THEN** system keeps those filters unchanged and applies them together with the new node scope

### Requirement: Distinct node options

The system SHALL list the distinct node values present in the shared `logs` table as selectable options for the node filter. The list SHALL reflect nodes recently observed in the table, SHALL be ordered for scanning, and SHALL exclude no node merely because it is absent from the current page of rows.

#### Scenario: Known nodes are offered as options

- **WHEN** the table contains rows from `my_app@10.0.0.5` and `my_app@10.0.0.6`
- **THEN** system offers both values as node options

#### Scenario: Options are independent of the current page

- **WHEN** the current page shows rows from only one node while the table holds more nodes
- **THEN** system still offers every distinct node, not only the nodes on the page

#### Scenario: Empty table offers no node options

- **WHEN** the table holds no rows with a node value
- **THEN** system offers no node options and the text input remains usable

### Requirement: Export the current page as raw text

The system SHALL offer an export of the rows currently shown on the viewer, as a plain-text file the browser downloads. The export SHALL cover exactly the rows on the current page, under the node, search, datetime-range, level, and page-size filters and the current page position in effect when the export is taken. It SHALL NOT include rows from other pages and SHALL NOT widen the scope to the whole filtered result set.

Each exported line SHALL carry the UTC `timestamp`, the `level`, the `node`, the untruncated `message`, and the source location when the row has one, so that a line can be matched back to the row it came from. A row with no node SHALL be exported as an explicit placeholder rather than as an empty field. Lines SHALL be ordered newest-first by `timestamp`, matching the order on the page.

The exported message SHALL be the message as stored, not the shortened text shown on the row. A message containing newlines SHALL be rendered in a way that keeps one exported record's fields together rather than interleaving them with the next record's fields.

The file SHALL be served as plain text with a name that identifies it as a log export, and the download SHALL NOT change the page's filters, its page position, or the rows shown.

#### Scenario: Exporting downloads a plain-text file

- **WHEN** user triggers the export
- **THEN** the browser downloads a plain-text file of the current page's rows

#### Scenario: The export covers the current page only

- **WHEN** user exports from a page that is not the first page
- **THEN** the file contains exactly the rows shown on that page and no rows from
  any other page

#### Scenario: The export honours the active filters

- **WHEN** user exports while a node scope, search, datetime range, and level are
  active
- **THEN** the file contains only rows matching those filters

#### Scenario: The export honours the active page position

- **WHEN** user exports after advancing to a later page
- **THEN** the file contains the rows of that page rather than restarting from
  the first page

#### Scenario: Each line carries timestamp, level, node, and message

- **WHEN** user exports a page
- **THEN** each line carries the row's UTC `timestamp`, its `level`, its
  `node`, and its `message`

#### Scenario: A line carries the source location when the row has one

- **WHEN** an exported row carries `module`/`function`/`file`/`line`
- **THEN** that line carries the source location

#### Scenario: A row with no node exports a placeholder

- **WHEN** an exported row has no `node`
- **THEN** that line shows an explicit placeholder rather than an empty field

#### Scenario: The exported message is not the shortened text

- **WHEN** user exports a page containing a row whose message is too long to
  show on one line
- **THEN** that line carries the full untruncated message

#### Scenario: A multi-line message does not interleave with the next record

- **WHEN** an exported row's message contains newlines
- **THEN** the fields of the following record are not interleaved into that
  message, and each record's fields stay together

#### Scenario: Exporting preserves newest-first order

- **WHEN** user exports a page
- **THEN** the lines appear in the same newest-first order as the rows on the
  page

#### Scenario: Exporting does not disturb the page

- **WHEN** user triggers the export
- **THEN** the page's filters, its page position, and the rows shown are
  unchanged

#### Scenario: Exporting an empty page yields an empty file

- **WHEN** user exports a page showing no rows
- **THEN** the download succeeds and the file contains no rows

### Requirement: Copy log row as text

The system SHALL offer a per-row action that copies that row's full record as text, carrying the UTC `timestamp`, the `level`, the `node` (or the explicit placeholder for a row with no node), the untruncated `message`, and the source location when the row has one. The copied text SHALL use the same field order and escaping as the page export, and copying SHALL NOT change the page's filters, its page position, or the rows shown.

#### Scenario: Copying a row copies its full info

- **WHEN** user triggers the copy action on a row
- **THEN** the clipboard receives that row's UTC `timestamp`, `level`, `node`, untruncated `message`, and source location when present

#### Scenario: Copying a node-less row uses the placeholder

- **WHEN** user copies a row whose `node` is absent
- **THEN** the copied text carries the explicit node placeholder rather than an empty field

#### Scenario: Copying carries the untruncated message

- **WHEN** user copies a row whose message is shortened on the row
- **THEN** the copied text carries the full untruncated message

#### Scenario: Copying does not disturb the page

- **WHEN** user copies a row
- **THEN** the page's filters, its page position, and the rows shown are unchanged

### Requirement: Logs-to-analysis handoff

The system SHALL offer a handoff action on the Logs page that navigates to `/analysis` carrying the active `node`, `search`, `from`, `to`, and `level` filters, so the Analysis page opens on the same scope without retyping. The handoff SHALL preserve every active filter value as typed and SHALL NOT alter the Logs page filters, page position, or rows shown.

#### Scenario: Handoff carries active filters to analysis

- **WHEN** user triggers the handoff with node, search, datetime-range, and level filters active on the Logs page
- **THEN** the Analysis page opens with those same node, search, datetime-range, and level values applied

#### Scenario: Handoff with no filters opens unscoped analysis

- **WHEN** user triggers the handoff with no filters active on the Logs page
- **THEN** the Analysis page opens in whole-system scope with no search keyword

#### Scenario: Handoff does not disturb the Logs page

- **WHEN** user triggers the handoff
- **THEN** the Logs page filters, page position, and rows shown are unchanged

### Requirement: Level filter layout

The system SHALL render exactly one level selector on the Logs page, consisting of the clickable level toggle options plus the `all` reset option, placed inside the filter card as its own full-width row. The level row SHALL NOT overlap, clip, or cover the node, search, datetime-range, per-page, or action controls at any viewport width. The filter card grid SHALL wrap cleanly: inputs occupy their own grid cells on wide screens and stack vertically without overlap on narrow screens.

#### Scenario: Single level control inside the filter card

- **WHEN** user opens the Logs page
- **THEN** the page shows exactly one level selector (toggle options plus `all`) and it sits inside the filter card on its own row

#### Scenario: Level selector does not overlap other controls on desktop

- **WHEN** user views the Logs page filter card on a wide viewport
- **THEN** the level row, node input, search input, datetime inputs, per-page select, and action buttons each occupy distinct non-overlapping areas

#### Scenario: Level selector does not overlap other controls on narrow screens

- **WHEN** user views the Logs page filter card on a narrow viewport
- **THEN** the level row and every other filter input stack vertically with no overlap or clipping

#### Scenario: Level toggle behaviour is unchanged

- **WHEN** user clicks a level option on the redesigned Logs filter
- **THEN** the system toggles that level in or out of the active set without disturbing the other active filters, exactly as before

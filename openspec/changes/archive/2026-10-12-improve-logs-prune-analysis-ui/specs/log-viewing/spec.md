# Spec Delta

## MODIFIED Requirements

### Requirement: Node-scoped log listing
The system SHALL list log rows from the shared `logs` table scoped to zero, one, or more selected nodes, defaulting to newest-first by `timestamp`. A scope with no selected node SHALL include every node, including rows where `node` is NULL. A scope with one or more selected nodes SHALL match rows whose `node` equals any selected value.

Each row SHALL be rendered as a single line rather than as a stacked card, carrying the UTC `timestamp`, `level`, `node`, `message`, and the available source location on that one line. The row SHALL carry a visual accent keyed to its level so that `error` and `warning` rows are distinguishable while scanning. Level SHALL remain readable as text and SHALL NOT be conveyed by color alone. The list SHALL present explicit columns for `timestamp`, `level`, `node`, `message`, and source location, and the columns SHALL be resizable by the user without changing the rows, filters, or page position.

A row SHALL NOT exceed a single line's height. A `message` too long to fit within the available width SHALL be shortened with a trailing ellipsis on the row, and the untruncated message SHALL remain reachable: it is exposed on hover and shown in full when that row is expanded. Nothing in the shortening SHALL be discarded from the system, and the export of that page SHALL carry the untruncated message. Expanding a row SHALL reveal the full `message` and, when the row carries them, its `metadata`; it SHALL NOT change the page's filters, its page position, or the rows on the page. Expansion SHALL be multi-open: expanding a row SHALL NOT collapse any other expanded row.

Spacing between and within rows SHALL be tight enough that the rows in a page are legible as a continuous list rather than as separated cards. Filter badges, inputs, and actions SHALL use the shell's shared visual language, and every badge and row action SHALL show a visible keyboard-focus indicator and remain operable by keyboard. Validation errors SHALL name the rejected field in text and SHALL NOT rely on color alone.

#### Scenario: View logs for a node
- **WHEN** user selects node `my_app@10.0.0.5`
- **THEN** system shows only rows where `node` equals that value ordered by `timestamp` descending

#### Scenario: View logs for multiple nodes
- **WHEN** user selects nodes `my_app@10.0.0.5` and `my_app@10.0.0.6`
- **THEN** system shows rows where `node` equals either selected value, ordered by `timestamp` descending

#### Scenario: View logs for whole system
- **WHEN** user selects no node
- **THEN** system shows rows from all nodes including rows where `node` is NULL, ordered by `timestamp` descending

#### Scenario: Node values are bound, not interpolated
- **WHEN** user supplies one or more node values
- **THEN** system matches them with bound parameters and no node text reaches the SQL string

#### Scenario: Log row contents
- **WHEN** a log row is rendered
- **THEN** system shows `timestamp` (UTC), `level`, `node`, `message`, and available `module`/`function`/`file`/`line`/`metadata`

#### Scenario: A row occupies a single line
- **WHEN** a log row is rendered
- **THEN** its `timestamp`, `level`, `node`, `message`, and available source location all appear on one line, and the row is no taller than one line

#### Scenario: An over-long message is shortened on the row
- **WHEN** a row's `message` is longer than the available width
- **THEN** the row shows the message shortened with a trailing ellipsis, does not grow taller than one line, and does not wrap

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
- **THEN** the page's filters, its page position, and the rows shown are unchanged

#### Scenario: Expanding a second row keeps the first expanded
- **WHEN** user expands a row while another row on the same page is already expanded
- **THEN** both rows show their full messages and neither row collapses

#### Scenario: Collapsing one expanded row keeps the others expanded
- **WHEN** user collapses an expanded row while other rows on the same page are expanded
- **THEN** only that row collapses and the other expanded rows stay expanded

#### Scenario: Expand-all expands every row on the page
- **WHEN** user triggers `Expand all messages`
- **THEN** every row on the current page shows its full message and metadata section when present

#### Scenario: Collapse-all collapses every expanded row
- **WHEN** user triggers `Collapse all messages` while rows are expanded
- **THEN** all rows return to single-line height and no expanded panel remains

#### Scenario: A row with no metadata expands to its message alone
- **WHEN** user expands a row whose `metadata` is empty
- **THEN** the full message is shown and no empty metadata section is offered

#### Scenario: Non-empty metadata is shown
- **WHEN** a log row carries a non-empty `metadata` map
- **THEN** system shows that metadata with the row once the row is expanded

#### Scenario: Level is distinguishable by accent and readable as text
- **WHEN** rows of differing levels are shown together
- **THEN** each row's accent corresponds to its level and the level remains present as text

#### Scenario: Rows read as a continuous list
- **WHEN** a page shows several rows
- **THEN** the spacing within and between the rows is tight enough that the page reads as a continuous list of log lines rather than as separated cards

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
- **THEN** they use the shell's shared styling for the same elements, so a control learned on another page is recognizable here

#### Scenario: Row and badge actions are keyboard operable with visible focus
- **WHEN** user tabs through level badges, node options, and row actions
- **THEN** each focused control shows a visible focus indicator and activates from the keyboard

#### Scenario: Filter errors name the field in text
- **WHEN** user submits a filter the system rejects
- **THEN** the error names the rejected field in text rather than relying on color alone

### Requirement: Multi-value node input
The system SHALL accept a node scope of zero, one, or more node names selected only through the clickable known-node options; it SHALL offer no free-text node input. An empty scope means all nodes. It SHALL display the active node scope on the page and provide a single action that clears the node filter back to all nodes plus a select-all action that returns to all nodes. Clicking an option SHALL toggle that node in or out of the active scope without disturbing the other active filters.

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

#### Scenario: Select-all returns to whole-system scope
- **WHEN** user triggers select-all while one or more nodes are selected
- **THEN** system clears the node scope to all nodes and refreshes the rows with the other active filters unchanged

#### Scenario: No free-text node input is offered
- **WHEN** user views the Logs page filter
- **THEN** no comma-separated node text field is present; node scope changes only through the badge options, select-all, or clear actions

#### Scenario: Node scope arrives only through validated options
- **WHEN** the page applies a node scope
- **THEN** every node value travels through the `node` URL param and bound parameters, and no raw node text reaches the SQL string

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
- **THEN** system offers no node options and the scope remains whole-system with select-all and clear actions hidden or disabled

## ADDED Requirements

### Requirement: Filter auto-apply with Refresh
The system SHALL apply Logs filter changes immediately through the URL params with no Apply step, and SHALL offer a Refresh action that re-runs the current filter set. Search text commits on change or submit, never per keystroke.

#### Scenario: Toggling a node refetches immediately
- **WHEN** user toggles a node badge, level badge, time shortcut, picker value, or page size
- **THEN** system updates the URL params and shows rows for the new filter set with no Apply press

#### Scenario: No Apply or Reset actions exist
- **WHEN** user views the Logs filter card
- **THEN** no Apply-filters or Reset button is present; a Refresh button is present instead

#### Scenario: Refresh re-runs the current filters
- **WHEN** user triggers Refresh with filters active
- **THEN** system re-runs the same node, search, datetime-range, level, and pagination params and shows the newest matching rows

#### Scenario: Search does not fetch per keystroke
- **WHEN** user types in the search field without committing
- **THEN** system runs no query until the field is committed by change or submit

#### Scenario: Rejected filter still shows its error with no total
- **WHEN** an auto-applied filter is rejected
- **THEN** system shows the validation error naming the field and shows no stale total or stale rows

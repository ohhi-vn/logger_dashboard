# Spec Delta

## MODIFIED Requirements

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

### Requirement: Level filter

The system SHALL filter by log level for `error`, `warning`, `info`, `debug`, plus `all`. It SHALL present each level as a clickable option, and clicking an option SHALL select that level as the active level filter. Selecting `all` SHALL apply no level predicate.

#### Scenario: Filter by single level

- **WHEN** user selects level `error`
- **THEN** system returns only rows where `level` equals `error`

#### Scenario: All levels

- **WHEN** user selects `all`
- **THEN** system applies no level predicate

#### Scenario: Clicking a level selects it

- **WHEN** user clicks the `warning` level option
- **THEN** system shows only rows where `level` equals `warning` and marks `warning` as the active level

#### Scenario: Clicking levels replaces the previous level

- **WHEN** user clicks level `info` while level `error` is active
- **THEN** system shows only rows where `level` equals `info`

#### Scenario: Clicking all clears the level filter

- **WHEN** user clicks the `all` level option while a single level is active
- **THEN** system applies no level predicate and marks `all` as active

### Requirement: Node-scoped log listing

The system SHALL list log rows from the shared `logs` table scoped to zero, one, or more selected nodes, defaulting to newest-first by `timestamp`. A scope with no selected node SHALL include every node, including rows where `node` is NULL. A scope with one or more selected nodes SHALL match rows whose `node` equals any selected value.

Each row SHALL be rendered as a single line rather than as a stacked card, carrying the UTC `timestamp`, `level`, `node`, `message`, and the available source location on that one line. The row SHALL carry a visual accent keyed to its level so that `error` and `warning` rows are distinguishable while scanning. Level SHALL remain readable as text and SHALL NOT be conveyed by color alone. The list SHALL present explicit columns for `timestamp`, `level`, `node`, `message`, and source location, and the columns SHALL be resizable by the user without changing the rows, filters, or page position.

A row SHALL NOT exceed a single line's height. A `message` too long to fit within the available width SHALL be shortened with a trailing ellipsis on the row, and the untruncated message SHALL remain reachable: it is exposed on hover and shown in full when that row is expanded. Nothing in the shortening SHALL be discarded from the system, and the export of that page SHALL carry the untruncated message. Expanding a row SHALL reveal the full `message` and, when the row carries them, its `metadata`; it SHALL NOT change the page's filters, its page position, or the rows on the page.

Spacing between and within rows SHALL be tight enough that the rows in a page are legible as a continuous list rather than as separated cards.

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

## ADDED Requirements

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

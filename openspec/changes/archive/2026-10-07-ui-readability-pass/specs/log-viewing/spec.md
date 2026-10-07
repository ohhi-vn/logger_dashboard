# Spec Delta

## MODIFIED Requirements

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

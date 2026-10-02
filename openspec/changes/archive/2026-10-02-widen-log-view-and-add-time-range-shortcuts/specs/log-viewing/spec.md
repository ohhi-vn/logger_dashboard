# Spec Delta

## MODIFIED Requirements

### Requirement: Node-scoped log listing

The system SHALL list log rows from the shared `logs` table scoped to zero, one, or more selected nodes, defaulting to newest-first by `timestamp`. A scope with no selected node SHALL include every node, including rows where `node` is NULL. A scope with one or more selected nodes SHALL match rows whose `node` equals any selected value.

Each row SHALL be rendered compactly as two lines rather than as a stacked card: a header line carrying `node`, `timestamp` (UTC), and `level`, followed by a body line carrying `message` and the available source location. The row SHALL carry a visual accent keyed to its level so that `error` and `warning` rows are distinguishable while scanning. Level SHALL remain readable as text and SHALL NOT be conveyed by color alone.

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

#### Scenario: Log row header carries node, datetime, and level

- **WHEN** a log row is rendered
- **THEN** its header line shows `node`, the UTC `timestamp`, and `level`

#### Scenario: Log row body carries message and source location

- **WHEN** a log row is rendered
- **THEN** its body line shows `message` and, when the row has them,
  `module`/`function`/`file`/`line`

#### Scenario: Non-empty metadata is shown

- **WHEN** a log row carries a non-empty `metadata` map
- **THEN** system shows that metadata with the row

#### Scenario: Level is distinguishable by accent and readable as text

- **WHEN** rows of differing levels are shown together
- **THEN** each row's accent corresponds to its level and the level remains
  present as text

#### Scenario: A long message is not truncated to fit the column

- **WHEN** a row's `message` is longer than the available width
- **THEN** system shows the whole message, wrapping as needed, without
  discarding any of it

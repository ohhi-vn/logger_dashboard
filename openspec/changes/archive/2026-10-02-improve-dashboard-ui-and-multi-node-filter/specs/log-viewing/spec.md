# Spec Delta

## MODIFIED Requirements

### Requirement: Node-scoped log listing

The system SHALL list log rows from the shared `logs` table scoped to zero, one, or more selected nodes, defaulting to newest-first by `timestamp`. A scope with no selected node SHALL include every node, including rows where `node` is NULL. A scope with one or more selected nodes SHALL match rows whose `node` equals any selected value.

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

## ADDED Requirements

### Requirement: Multi-value node input

The system SHALL accept a node filter containing one or more node names separated by commas. It SHALL trim surrounding whitespace from each entry, ignore blank entries, and treat an input that reduces to no entries as "all nodes". It SHALL display the active node scope on the page and provide a single action that clears the node filter back to all nodes.

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

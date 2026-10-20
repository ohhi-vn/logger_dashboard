# Spec Delta

## MODIFIED Requirements

### Requirement: Distinct node options

The system SHALL list the distinct node values present in the shared `logs` table as selectable options for the node filter, together with every node in the active scope. The list SHALL reflect nodes recently observed in the table, SHALL be ordered for scanning, and SHALL exclude no node merely because it is absent from the current page of rows. A node in the active scope that is not among the known node values SHALL be offered ahead of them, so that the scope is visible and removable through the options.

#### Scenario: Known nodes are offered as options
- **WHEN** the table contains rows from `my_app@10.0.0.5` and `my_app@10.0.0.6`
- **THEN** system offers both values as node options

#### Scenario: Options are independent of the current page
- **WHEN** the current page shows rows from only one node while the table holds more nodes
- **THEN** system still offers every distinct node, not only the nodes on the page

#### Scenario: Empty table offers no node options
- **WHEN** the table holds no rows with a node value
- **THEN** system offers no node options and the scope remains whole-system with select-all and clear actions hidden or disabled

#### Scenario: An active node outside the known node list is offered ahead of them
- **WHEN** the active scope names a node that is not among the known node values
- **THEN** the node options offer that node first, marked as in scope, so it can be seen and removed

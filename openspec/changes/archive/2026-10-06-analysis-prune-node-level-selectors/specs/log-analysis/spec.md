# Spec Delta

## MODIFIED Requirements

### Requirement: System or node analysis scope

The system SHALL compute analytics scoped to all nodes, one node, or multiple nodes, reusing the viewer filter semantics for `node`, datetime range, and level. It SHALL present the known nodes as clickable options alongside the text input, and clicking an option SHALL toggle that node in or out of the active scope without disturbing the other active filters. It SHALL present each level as a clickable option, and clicking an option SHALL select that level as the active level filter.

#### Scenario: Analyze whole system

- **WHEN** user opens analysis with no node selected
- **THEN** system aggregates rows from all nodes for the selected time range

#### Scenario: Analyze single node

- **WHEN** user selects node `my_app@10.0.0.5` on the analysis page
- **THEN** system aggregates only rows where `node` equals that value

#### Scenario: Analyze multiple nodes

- **WHEN** user selects nodes `my_app@10.0.0.5` and `my_app@10.0.0.6` on the analysis page
- **THEN** system aggregates only rows whose `node` equals either selected value

#### Scenario: Multi-node analysis combines with range and level

- **WHEN** user selects multiple nodes together with a datetime range and level
- **THEN** system aggregates rows matching the node set, the range, and the level

#### Scenario: Clicking an unselected node adds it to the analysis scope

- **WHEN** user clicks a node option that is not in the active scope on the analysis page
- **THEN** system adds that node to the scope and recomputes the analysis while keeping range, level, and bucket unchanged

#### Scenario: Clicking a selected node removes it from the analysis scope

- **WHEN** user clicks a node option that is already in the active scope on the analysis page
- **THEN** system removes that node from the scope, and removing the last selected node returns to all nodes

#### Scenario: Clicking a level selects it for analysis

- **WHEN** user clicks the `warning` level option on the analysis page
- **THEN** system aggregates only rows where `level` equals `warning` and marks `warning` as the active level

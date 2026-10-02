# Spec Delta

## MODIFIED Requirements

### Requirement: System or node analysis scope

The system SHALL compute analytics scoped to all nodes, one node, or multiple nodes, reusing the viewer filter semantics for `node`, datetime range, and level.

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

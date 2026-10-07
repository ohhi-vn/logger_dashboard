# Spec Delta

## MODIFIED Requirements

### Requirement: System or node analysis scope

The system SHALL compute analytics scoped to all nodes, one node, or multiple nodes, reusing the viewer filter semantics for `node`, datetime range, level, and `search` keyword. It SHALL present the known nodes as clickable options alongside the text input, and clicking an option SHALL toggle that node in or out of the active scope without disturbing the other active filters. It SHALL present each level as a clickable toggle option plus an `all` reset option, and clicking a level option SHALL toggle that level in or out of the active level set without disturbing the other active filters. An empty level set, or selecting `all`, SHALL apply no level predicate; a non-empty level set SHALL aggregate only rows whose `level` equals any selected value. The `level` URL param SHALL accept a comma-separated list (e.g. `level=error,warning`); a single value, `all`, absent, or blank SHALL keep working as a one-element or empty set, and an unknown level value SHALL reject the filter with a validation error and run no analysis. It SHALL accept a `search` keyword using the same wildcard syntax as the viewer (`*` = any run, `?` = single char) and SHALL apply it as a database-evaluated predicate over `message` together with the node, range, and level predicates. An empty or absent `search` SHALL apply no message predicate. The system SHALL accept handoff params (`node`, `search`, `from`, `to`, `level`, `bucket`) navigated from the Logs page and SHALL treat them identically to hand-entered values, including a multi-level `level` value.

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

- **WHEN** user selects multiple nodes together with a datetime range and levels `error,warning`
- **THEN** system aggregates rows matching the node set, the range, and either level

#### Scenario: Clicking an unselected node adds it to the analysis scope

- **WHEN** user clicks a node option that is not in the active scope on the analysis page
- **THEN** system adds that node to the scope and recomputes the analysis while keeping range, level, and bucket unchanged

#### Scenario: Clicking a selected node removes it from the analysis scope

- **WHEN** user clicks a node option that is already in the active scope on the analysis page
- **THEN** system removes that node from the scope, and removing the last selected node returns to all nodes

#### Scenario: Clicking a level toggles it for analysis

- **WHEN** user clicks the `warning` level option on the analysis page while no level is active
- **THEN** system aggregates only rows where `level` equals `warning` and marks `warning` as active

#### Scenario: Clicking a level selects it for analysis

- **WHEN** user clicks the `warning` level option on the analysis page
- **THEN** system aggregates only rows where `level` equals `warning` and marks `warning` as the active level

#### Scenario: Clicking a second level widens analysis to both levels

- **WHEN** user clicks the `error` level option on the analysis page while `warning` is active
- **THEN** system aggregates rows where `level` equals `error` or `warning` and marks both as active

#### Scenario: Clicking all clears the analysis level filter

- **WHEN** user clicks the `all` level option on the analysis page while one or more levels are active
- **THEN** system applies no level predicate and marks `all` as active

#### Scenario: Keyword narrows every analysis

- **WHEN** user enters search `*timeout*` together with a node scope, datetime range, and level set
- **THEN** level frequency, volume over time, and per-node counts each aggregate only rows whose `message` matches that pattern within the scope

#### Scenario: Empty search means unfiltered messages

- **WHEN** user runs analysis with an empty search value
- **THEN** system applies no message predicate

#### Scenario: Handoff from Logs opens the same scope

- **WHEN** user arrives at analysis via the Logs handoff carrying node, search, datetime-range, and a multi-level `level=error,warning` value
- **THEN** system applies those values as the active scope and shows them in the filter inputs

#### Scenario: Invalid analysis level rejected

- **WHEN** user opens analysis with `level=bogus`
- **THEN** system rejects the filter with a validation error and renders no analysis result

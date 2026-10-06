# Spec Delta

## MODIFIED Requirements

### Requirement: System or node analysis scope

The system SHALL compute analytics scoped to all nodes, one node, or multiple nodes, reusing the viewer filter semantics for `node`, datetime range, level, and `search` keyword. It SHALL present the known nodes as clickable options alongside the text input, and clicking an option SHALL toggle that node in or out of the active scope without disturbing the other active filters. It SHALL present each level as a clickable option, and clicking an option SHALL select that level as the active level filter. It SHALL accept a `search` keyword using the same wildcard syntax as the viewer (`*` = any run, `?` = single char) and SHALL apply it as a database-evaluated predicate over `message` together with the node, range, and level predicates. An empty or absent `search` SHALL apply no message predicate. The system SHALL accept handoff params (`node`, `search`, `from`, `to`, `level`, `bucket`) navigated from the Logs page and SHALL treat them identically to hand-entered values.

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

#### Scenario: Keyword narrows every analysis

- **WHEN** user enters search `*timeout*` together with a node scope, datetime range, and level
- **THEN** level frequency, volume over time, and per-node counts each aggregate only rows whose `message` matches that pattern within the scope

#### Scenario: Empty search means unfiltered messages

- **WHEN** user runs analysis with an empty search value
- **THEN** system applies no message predicate

#### Scenario: Handoff from Logs opens the same scope

- **WHEN** user arrives at analysis via the Logs handoff carrying node, search, datetime-range, and level values
- **THEN** system applies those values as the active scope and shows them in the filter inputs

## ADDED Requirements

### Requirement: Keyword-filtered breakdowns stay bounded and disclosed

The system SHALL compute each keyword-filtered breakdown (count-by-`level`, volume bucketed by time, per-`node` counts) over a bounded set of rows and SHALL disclose that bound alongside the result. Level ordering (descending by count) and time-bucket chronology SHALL hold for keyword-filtered results exactly as for unfiltered ones. A keyword scope matching no rows SHALL render empty tables rather than failing, and a rejected filter SHALL render no analysis result.

#### Scenario: Keyword level mix stays ordered and bounded

- **WHEN** analysis runs with a search keyword whose matches exceed the applied analysis bound
- **THEN** system lists levels largest-first, states the counts come from a bounded set, and does not present them as exact totals

#### Scenario: Keyword volume renders every produced series

- **WHEN** keyword-filtered volume is split by level
- **THEN** system renders a value for every series the analysis produced, naming each series

#### Scenario: Keyword scope with no matches renders empty

- **WHEN** the keyword, node scope, and range match no rows
- **THEN** system renders empty level, volume, and node tables rather than failing

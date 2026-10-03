# Log Analysis Specification

## Purpose

Gives operators system-wide and per-node log analytics (volume, level mix, node breakdown) over the same ClickHouse logs without writing queries.

## Requirements

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

### Requirement: Level frequency breakdown

The system SHALL show count-by-`level` for the active scope and time range, ordered descending by count, computed over a bounded set of rows, and SHALL disclose that bound alongside the result.

#### Scenario: Frequency by level

- **WHEN** analysis runs for a 24h range
- **THEN** system shows per-level counts (error, warning, info, debug) for the rows it analyzed

#### Scenario: Highest level first

- **WHEN** analysis runs and one level has more matching rows than another
- **THEN** system lists that level ahead of the level with fewer rows, so the dominant level is the first one read

#### Scenario: Counts are bounded, not totals

- **WHEN** the rows matching the scope and range exceed the applied analysis bound
- **THEN** system states that the counts were computed from a bounded set of rows and do not present them as the exact totals for the scope and range

### Requirement: Volume over time

The system SHALL show log volume bucketed by time (`minute`/`hour`/`day` selectable, default `hour`) for the active scope, and SHALL render a value for every series the volume analysis produced, naming each series.

#### Scenario: Time-bucketed volume

- **WHEN** user selects bucket `day` for the last 7 days
- **THEN** system shows one label per day with total count per day, optionally split by `level`

#### Scenario: Split volume attributes every value it shows

- **WHEN** volume is split by `level` and the analysis produced a series per level
- **THEN** system renders a value for every one of those series and names each one, so no level's count is presented without saying which level it belongs to

#### Scenario: Unsplit volume still reads as label and count

- **WHEN** volume is not split and the analysis produced a single series
- **THEN** system renders one value per label under that series' name

#### Scenario: An empty scope renders no rows

- **WHEN** the scope and range match no rows
- **THEN** system renders the volume result as an empty table rather than failing

### Requirement: Per-node breakdown

The system SHALL show per-`node` counts when in system scope so hot/spammy nodes are visible.

#### Scenario: Top nodes table

- **WHEN** analysis runs in "All nodes" scope
- **THEN** system shows a table of `node` to count ordered descending, rolling NULL-node rows into an explicit `unknown` entry

### Requirement: Bounded analysis with limit disclosure

The system SHALL bound every analysis read by an explicit row limit and disclose when results are computed from a bounded sample.

#### Scenario: Limit enforced and disclosed

- **WHEN** the matching rows exceed the configured `max_limit`
- **THEN** system computes over at most `max_limit` rows and displays the applied limit alongside the charts

### Requirement: Analysis page state matches the query it ran

The system SHALL render analysis page state that corresponds to the query the server actually executed, and SHALL render no analysis result for a request it rejected.

#### Scenario: Bucket control shows the applied bucket

- **WHEN** user opens analysis with bucket `day` in effect
- **THEN** system marks `day` as the selected option in the bucket control, so the control does not display a bucket different from the one the displayed results were computed with

#### Scenario: An unrecognized bucket falls back visibly

- **WHEN** user opens analysis with a bucket value the system does not support
- **THEN** system computes results with the default bucket and marks that default as selected in the bucket control

#### Scenario: A rejected filter leaves no results behind

- **WHEN** analysis has rendered results and user submits a request whose filter is rejected
- **THEN** system shows the rejection and renders no volume, level, or node result, rather than leaving the previous request's results in place

#### Scenario: Substituting a control keeps the chosen bucket

- **WHEN** user changes only the node scope while a bucket is selected and submits the form
- **THEN** system still applies that bucket

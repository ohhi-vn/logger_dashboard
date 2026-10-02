# Log Analysis Specification

## Purpose

Gives operators system-wide and per-node log analytics (volume, level mix, node breakdown) over the same ClickHouse logs without writing queries.

## Requirements

### Requirement: System or node analysis scope

The system SHALL compute analytics scoped to all nodes or to one selected node, reusing the viewer filter semantics for `node`, datetime range, and level.

#### Scenario: Analyze whole system

- **WHEN** user opens analysis with scope "All nodes"
- **THEN** system aggregates rows from all nodes for the selected time range

#### Scenario: Analyze single node

- **WHEN** user selects node `my_app@10.0.0.5` on the analysis page
- **THEN** system aggregates only rows where `node` equals that value

### Requirement: Level frequency breakdown

The system SHALL show count-by-`level` for the active scope and time range.

#### Scenario: Frequency by level

- **WHEN** analysis runs for a 24h range
- **THEN** system shows per-level counts (error, warning, info, debug) that sum to the filtered total

### Requirement: Volume over time

The system SHALL show log volume bucketed by time (`minute`/`hour`/`day` selectable, default `hour`) for the active scope.

#### Scenario: Time-bucketed volume

- **WHEN** user selects bucket `day` for the last 7 days
- **THEN** system shows one label per day with total count per day, optionally split by `level`

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

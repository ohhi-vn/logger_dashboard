# Spec Delta

## MODIFIED Requirements

### Requirement: Level frequency breakdown

The system SHALL show count-by-`level` for the active scope and time range, ordered descending by count, computed over a bounded set of rows, and SHALL disclose that bound alongside the result. The breakdown SHALL render as a legible table using the shell's shared table styling, with level readable as text rather than conveyed by color alone.

#### Scenario: Frequency by level

- **WHEN** analysis runs for a 24h range
- **THEN** system shows per-level counts (error, warning, info, debug) for the rows it analyzed

#### Scenario: Highest level first

- **WHEN** analysis runs and one level has more matching rows than another
- **THEN** system lists that level ahead of the level with fewer rows, so the dominant level is the first one read

#### Scenario: Counts are bounded, not totals

- **WHEN** the rows matching the scope and range exceed the applied analysis bound
- **THEN** system states that the counts were computed from a bounded set of rows and do not present them as the exact totals for the scope and range

#### Scenario: Breakdown uses shared table styling with text levels

- **WHEN** analysis shows the count-by-level table
- **THEN** the table uses the shell's shared table styling and each level is readable as text

### Requirement: Volume over time

The system SHALL show log volume bucketed by time (`minute`/`hour`/`day` selectable, default `hour`) for the active scope, and SHALL render a value for every series the volume analysis produced, naming each series. The volume table SHALL use the shell's shared table styling and remain legible at the same density as the other result tables.

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

The system SHALL show per-`node` counts when in system scope so hot/spammy nodes are visible. The breakdown SHALL render as a legible table using the shell's shared table styling.

#### Scenario: Top nodes table

- **WHEN** analysis runs in "All nodes" scope
- **THEN** system shows a table of `node` to count ordered descending, rolling NULL-node rows into an explicit `unknown` entry

#### Scenario: Node table uses shared table styling

- **WHEN** analysis shows the per-node table
- **THEN** the table uses the shell's shared table styling at the same density as the other result tables

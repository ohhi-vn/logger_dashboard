# Spec Delta

## MODIFIED Requirements

### Requirement: Level frequency breakdown

The system SHALL show count-by-`level` for the active scope and time range, ordered descending by count, computed over a bounded set of rows, and SHALL disclose that bound alongside the result. The breakdown SHALL render as a table using the shell's shared table styling at the same compact density as the other result tables, with level readable as text rather than conveyed by color alone.

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
- **THEN** the table uses the shell's shared table styling at the same compact density as the other result tables, and each level is readable as text

### Requirement: Volume over time

The system SHALL show log volume bucketed by time (`minute`/`hour`/`day` selectable, default `hour`) for the active scope, and SHALL render a value for every series the volume analysis produced, naming each series. The volume table SHALL use the shell's shared table styling at the same compact density as the other result tables, and remain legible.

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

The system SHALL show per-`node` counts when in system scope so hot/spammy nodes are visible. The breakdown SHALL render as a compact table using the shell's shared table styling, in one column of the breakdown grid rather than spanning the page, and bounded so that many nodes do not lengthen the page.

#### Scenario: Top nodes table

- **WHEN** analysis runs in "All nodes" scope
- **THEN** system shows a table of `node` to count ordered descending, rolling NULL-node rows into an explicit `unknown` entry

#### Scenario: Node table uses shared table styling

- **WHEN** analysis shows the per-node table
- **THEN** the table uses the shell's shared table styling at the same compact density as the other result tables

#### Scenario: The by-node breakdown is bounded

- **WHEN** the per-node analysis produced more nodes than fit in the region the breakdown occupies
- **THEN** the breakdown stays within that region and the page does not grow to the node count

### Requirement: Bounded analysis with limit disclosure

The system SHALL bound every analysis read by an explicit row limit and SHALL disclose the applied bound alongside the results. The disclosure SHALL name the number of rows the results were computed over and SHALL NOT refer to a setting the page does not offer.

#### Scenario: Limit enforced and disclosed

- **WHEN** the matching rows exceed the configured `max_limit`
- **THEN** system computes over at most `max_limit` rows and displays the applied limit alongside the results

#### Scenario: The disclosure names the applied bound

- **WHEN** the analysis page shows the applied limit
- **THEN** the disclosure names the number of rows the results were computed over and names no setting the page does not offer

## ADDED Requirements

### Requirement: Analysis breakdown grid

The three Analysis breakdowns — by level, by node, and volume over time — SHALL be laid out in one responsive grid, in the order by level, by node, volume over time. On a narrow viewport they SHALL stack in a single column. On an intermediate viewport the two frequency breakdowns SHALL sit side by side with the time series beneath them. On a wide viewport all three SHALL sit side by side, and the by-node breakdown SHALL occupy a share of the row narrower than the volume-over-time breakdown.

#### Scenario: Narrow viewport stacks the breakdowns

- **WHEN** user views the Analysis page on a narrow viewport
- **THEN** the three breakdowns are stacked in a single column

#### Scenario: Intermediate viewport pairs the frequency breakdowns

- **WHEN** user views the Analysis page on an intermediate viewport
- **THEN** the by-level and by-node breakdowns sit side by side, and the volume-over-time breakdown sits beneath them across the row

#### Scenario: Wide viewport shows the by-node breakdown in a column

- **WHEN** user views the Analysis page on a wide viewport
- **THEN** the by-node breakdown occupies one column of the row and does not span the full page width

#### Scenario: The breakdowns keep a fixed order

- **WHEN** user views the Analysis page
- **THEN** the breakdowns appear in the order by level, by node, volume over time

### Requirement: Bounded breakdown result tables

Each breakdown's result table SHALL render inside a bounded-height region that scrolls vertically, with the table's header row staying visible while the body scrolls. The three result tables SHALL use the shell's shared table styling at the same compact density. A breakdown reporting many rows SHALL remain fully reachable and SHALL NOT lengthen the page beyond its bounded region.

#### Scenario: A long breakdown scrolls instead of lengthening the page

- **WHEN** a breakdown's analysis produced more rows than fit in the region the breakdown occupies
- **THEN** the table scrolls within that region and the page does not grow to the row count

#### Scenario: The header stays visible while scrolling

- **WHEN** user scrolls a result table
- **THEN** the table's header row remains visible at the top of the region

#### Scenario: All three result tables share one density

- **WHEN** user views the by-level, by-node, and volume-over-time tables
- **THEN** all three use the shell's shared table styling at the same compact density

#### Scenario: Every produced row stays reachable

- **WHEN** a breakdown's analysis produced N rows
- **THEN** all N rows are present in the table and reachable by scrolling it

### Requirement: Bounded breakdown charts

Each breakdown's chart SHALL be drawn in a frame of a definite height, so that its height does not grow with the width of the column it sits in. The three breakdown charts SHALL share the same height, so the breakdown cards line up.

#### Scenario: The chart height does not follow the column width

- **WHEN** user views the Analysis page on a wide viewport, where each breakdown sits in a narrower column
- **THEN** each breakdown's chart is the same height it is on a narrow viewport

#### Scenario: The three charts share one height

- **WHEN** user views the Analysis page
- **THEN** the by-level, by-node, and volume-over-time charts are drawn at the same height

### Requirement: Chart style control labels

The chart-style control SHALL label each style with a readable name rather than a raw identifier, while the style identifier carried in the URL SHALL remain unchanged, so a shared link still selects the same chart.

#### Scenario: Styles are labelled readably

- **WHEN** user views a breakdown's style control
- **THEN** each offered style is labelled with a readable name rather than a raw identifier

#### Scenario: The label does not change the URL

- **WHEN** user picks a style
- **THEN** the URL carries the same style identifier it carried before, and the chart shown is the one that identifier selects

### Requirement: Analysis filter card rows

The Analysis filter card SHALL place the search input, the datetime range bounds, and the bucket control together on one row, the level options on their own full-width row, and the refresh and range-shortcut actions on the last row, leaving no row of the card partly empty on a wide viewport.

#### Scenario: The bucket control shares the range row

- **WHEN** user views the Analysis filter card on a wide viewport
- **THEN** the bucket control sits on the same row as the range bounds and the search input

#### Scenario: The level options keep their own row

- **WHEN** user views the Analysis filter card
- **THEN** the level options occupy a full-width row of their own

#### Scenario: No row of the card is left partly empty

- **WHEN** user views the Analysis filter card on a wide viewport
- **THEN** every row of the card is filled by its controls

### Requirement: The Analysis page states the node scope through its node options

The Analysis page SHALL state the active node scope through the node scope control alone, and SHALL NOT render a separate list of the active nodes beside it.

#### Scenario: No separate active-node list is rendered

- **WHEN** user views the Analysis page
- **THEN** the page shows no separate summary list of the active nodes beside the node options

#### Scenario: The active scope is visible through the node options

- **WHEN** user views the Analysis page with nodes in scope
- **THEN** each of those nodes is offered by the node options and marked as in scope

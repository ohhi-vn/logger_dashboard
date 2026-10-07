# Log Analysis Specification

## Purpose

Gives operators system-wide and per-node log analytics (volume, level mix, node breakdown) over the same ClickHouse logs without writing queries.

## Requirements

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

### Requirement: Analysis level filter layout

The system SHALL render exactly one level selector on the Analysis page, consisting of the clickable level toggle options plus the `all` reset option, placed inside the filter card as its own full-width row. The level row SHALL NOT overlap, clip, or cover the node, search, datetime-range, bucket, or action controls at any viewport width. The filter card grid SHALL wrap cleanly: inputs occupy their own grid cells on wide screens and stack vertically without overlap on narrow screens.

#### Scenario: Single level control inside the analysis filter card

- **WHEN** user opens the Analysis page
- **THEN** the page shows exactly one level selector (toggle options plus `all`) and it sits inside the filter card on its own row

#### Scenario: Analysis level selector does not overlap other controls on desktop

- **WHEN** user views the Analysis page filter card on a wide viewport
- **THEN** the level row, node input, search input, datetime inputs, bucket select, and action buttons each occupy distinct non-overlapping areas

#### Scenario: Analysis level selector does not overlap other controls on narrow screens

- **WHEN** user views the Analysis page filter card on a narrow viewport
- **THEN** the level row and every other filter input stack vertically with no overlap or clipping

#### Scenario: Analysis level toggle behaviour is unchanged

- **WHEN** user clicks a level option on the redesigned Analysis filter
- **THEN** the system toggles that level in or out of the active set without disturbing node, range, search, or bucket, exactly as before

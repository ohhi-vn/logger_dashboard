# Spec Delta

## MODIFIED Requirements

### Requirement: Level filter

The system SHALL filter by zero, one, or more log levels from `error`, `warning`, `info`, `debug`. It SHALL present each level as a clickable toggle option plus an `all` reset option, and clicking a level option SHALL toggle that level in or out of the active level set without disturbing the other active filters. An empty level set, or selecting `all`, SHALL apply no level predicate. A non-empty level set SHALL match rows whose `level` equals any selected value. The `level` URL param SHALL accept a comma-separated list (e.g. `level=error,warning`); a single value, `all`, absent, or blank SHALL keep working as a one-element or empty set. An unknown level value SHALL reject the filter with a validation error and run no query. Level values SHALL be matched with bound parameters and no level text reaches the SQL string.

#### Scenario: Filter by single level

- **WHEN** user selects level `error`
- **THEN** system returns only rows where `level` equals `error`

#### Scenario: Filter by multiple levels

- **WHEN** user selects levels `error` and `warning`
- **THEN** system returns only rows where `level` equals `error` or `warning`, ordered by `timestamp` descending

#### Scenario: All levels

- **WHEN** user selects `all` or selects no level
- **THEN** system applies no level predicate

#### Scenario: Clicking a level selects it

- **WHEN** user clicks the `warning` level option
- **THEN** system shows only rows where `level` equals `warning` and marks `warning` as the active level

#### Scenario: Clicking levels replaces the previous level

- **WHEN** user clicks level `info` while level `error` is active
- **THEN** system shows rows where `level` equals `error` or `info` (clicking adds to the set rather than replacing it)

#### Scenario: Clicking an unselected level adds it

- **WHEN** user clicks the `warning` level option while `error` is active
- **THEN** system shows rows where `level` equals `error` or `warning` and marks both as active

#### Scenario: Clicking a selected level removes it

- **WHEN** user clicks the `error` level option while `error` and `warning` are active
- **THEN** system shows only rows where `level` equals `warning`

#### Scenario: Removing the last level returns to all levels

- **WHEN** user clicks the only active level option
- **THEN** system applies no level predicate and marks `all` as active

#### Scenario: Clicking all clears the level filter

- **WHEN** user clicks the `all` level option while one or more levels are active
- **THEN** system applies no level predicate and marks `all` as active

#### Scenario: Single-level bookmark keeps working

- **WHEN** user opens `?level=error`
- **THEN** system applies a one-element `error` set and marks `error` as active

#### Scenario: Invalid level rejected

- **WHEN** user submits `level=verbose` or `level=error,bogus`
- **THEN** system rejects the filter with a validation error and runs no query

#### Scenario: Level values are bound, not interpolated

- **WHEN** user supplies one or more level values
- **THEN** system matches them with bound parameters and no level text reaches the SQL string

#### Scenario: Level combines with other active filters

- **WHEN** user selects levels `error,warning` together with a node scope, datetime range, and search pattern
- **THEN** system applies the level set only to rows already matching that scope, range, and pattern

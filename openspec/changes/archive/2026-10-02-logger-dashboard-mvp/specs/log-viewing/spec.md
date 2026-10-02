# Spec Delta

## Purpose

Lets operators browse logs shipped by `clickhouse_ex_logger` from a single place, scoped to one node or all nodes with fast time-pruned filtering.

## ADDED Requirements

### Requirement: Node-scoped log listing

The system SHALL list log rows from the shared `logs` table scoped to a selected node or to all nodes, defaulting to newest-first by `timestamp`.

#### Scenario: View logs for a node

- **WHEN** user selects node `my_app@10.0.0.5`
- **THEN** system shows only rows where `node` equals that value ordered by `timestamp` descending

#### Scenario: View logs for whole system

- **WHEN** user selects "All nodes" scope
- **THEN** system shows rows from all nodes including rows where `node` is NULL, ordered by `timestamp` descending

#### Scenario: Log row contents

- **WHEN** a log row is rendered
- **THEN** system shows `timestamp` (UTC), `level`, `node`, `message`, and available `module`/`function`/`file`/`line`/`metadata`

### Requirement: Wildcard text search

The system SHALL support wildcard text search over `message` (e.g. `*timeout*`, `db_*`) translated to a ClickHouse `LIKE`/`match` predicate.

#### Scenario: Wildcard search filters rows

- **WHEN** user enters `*timeout*` in search
- **THEN** system returns only rows whose `message` matches the wildcard pattern

#### Scenario: Empty search returns unfiltered messages

- **WHEN** search text is empty
- **THEN** system applies no message predicate

### Requirement: Datetime-range filter

The system SHALL filter by an explicit UTC datetime range on `timestamp` with inclusive bounds.

#### Scenario: Filter by datetime range

- **WHEN** user sets `from=2026-09-01T00:00:00Z` and `to=2026-09-02T00:00:00Z`
- **THEN** system returns only rows where `timestamp` is within that range

#### Scenario: Invalid range rejected

- **WHEN** user submits `from` after `to` or unparseable datetimes
- **THEN** system rejects the filter with a validation error and runs no query

### Requirement: Level filter

The system SHALL filter by log level for `error`, `warning`, `info`, `debug`, plus `all`.

#### Scenario: Filter by single level

- **WHEN** user selects level `error`
- **THEN** system returns only rows where `level` equals `error`

#### Scenario: All levels

- **WHEN** user selects `all`
- **THEN** system applies no level predicate

### Requirement: Paginated newest-first browsing

The system SHALL paginate log results with limit/offset and preserve active filters across pages.

#### Scenario: Paginate filtered logs

- **WHEN** user advances to the next page with filters active
- **THEN** system keeps node, search, datetime-range, and level filters and shows the next slice in `timestamp` descending order

#### Scenario: Empty result

- **WHEN** no rows match the active filters
- **THEN** system shows an empty state naming the active scope/filters

# Spec Delta

## MODIFIED Requirements

### Requirement: Wildcard text search

The system SHALL support wildcard text search over `message` (e.g. `*timeout*`, `db_*`) translated to a ClickHouse `LIKE`/`match` predicate. The predicate SHALL be evaluated by the database against every row in the active scope, not applied in application memory to a bounded subset.

#### Scenario: Wildcard search filters rows

- **WHEN** user enters `*timeout*` in search
- **THEN** system returns only rows whose `message` matches the wildcard pattern

#### Scenario: Empty search returns unfiltered messages

- **WHEN** search text is empty
- **THEN** system applies no message predicate

#### Scenario: Search matches beyond the most recent rows

- **WHEN** matching rows exist that are not among the most recent rows in the active scope
- **THEN** system still returns those matches, and returns them in the same pagination sequence as unsearched rows

#### Scenario: Search combines with other active filters

- **WHEN** user enters a search pattern together with a node scope, datetime range, and level
- **THEN** system applies the message pattern only to rows already matching that scope, range, and level

### Requirement: Paginated newest-first browsing

The system SHALL paginate log results with limit/offset and preserve active filters across pages. Pages SHALL be drawn from the complete set of rows matching the active filters.

#### Scenario: Paginate filtered logs

- **WHEN** user advances to the next page with filters active
- **THEN** system keeps node, search, datetime-range, and level filters and shows the next slice in `timestamp` descending order

#### Scenario: Empty result

- **WHEN** no rows match the active filters
- **THEN** system shows an empty state naming the active scope/filters

#### Scenario: Last page signals end of results

- **WHEN** a page returns fewer rows than the per-page limit
- **THEN** system indicates that no further pages exist and offers no way to advance past the last page

#### Scenario: Page size and scope are preserved when advancing

- **WHEN** user advances from a page and the active filters are unchanged
- **THEN** system keeps the per-page size and the active scope in the resulting page

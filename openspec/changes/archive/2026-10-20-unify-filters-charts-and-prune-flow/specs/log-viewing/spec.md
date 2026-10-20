# Spec Delta

## MODIFIED Requirements

### Requirement: Wildcard text search

The system SHALL support wildcard text search over `message` (e.g. `*timeout*`, `db_*`) translated to a ClickHouse case-insensitive `LIKE`/`match` predicate. The predicate SHALL be evaluated by the database against every row in the active scope, not applied in application memory to a bounded subset.

A search MAY carry several space-separated terms, and a row matches the search only when it matches every term. A term that carries a wildcard SHALL be matched as written; a term with no wildcard SHALL match anywhere in the message. Matching SHALL ignore letter case, so a term matches regardless of the case used in the message. A search whose wildcards span the whole string SHALL be matched as one pattern, so the spaces inside it are literal. An empty search SHALL continue to apply no message predicate.

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

#### Scenario: Search ignores letter case

- **WHEN** user enters `Timeout` and a row's message reads `connection timeout`
- **THEN** that row matches the search

#### Scenario: Several terms are combined with AND

- **WHEN** user enters `*timeout* *db*`
- **THEN** system returns only rows whose message matches both terms, not rows matching either one alone

#### Scenario: Each term keeps the wildcard syntax

- **WHEN** user enters `*timeout* db_*`
- **THEN** the first term matches any run of characters and the second matches a run beginning with `db`

#### Scenario: A wildcard search keeps its meaning

- **WHEN** user enters one wildcard term
- **THEN** the rows returned are the same rows that term returned before, apart from the comparison no longer depending on letter case

#### Scenario: A term without a wildcard matches anywhere in the message

- **WHEN** user enters `timeout`
- **THEN** system returns the rows whose message contains `timeout`, not only the rows whose message is exactly `timeout`

#### Scenario: A search whose wildcards span the whole string is one pattern

- **WHEN** user enters `*logtotal row 2*`
- **THEN** system returns the rows whose message contains that phrase, spaces included

## ADDED Requirements

### Requirement: The viewer presents the shared filter controls

The Logs page SHALL present its node scope, level scope, and search through the same shared controls the Analysis and Prune pages use, and SHALL NOT present a second, page-specific variant of any of them. The viewer's own controls — the per-page row count and the refresh action — SHALL remain on the page and SHALL continue to work as they do today.

#### Scenario: No duplicate node or level control on the viewer
- **WHEN** user views the Logs page filter
- **THEN** exactly one node scope control and exactly one level scope control are present

#### Scenario: The viewer's search states the shared syntax
- **WHEN** user views the search control on the Logs page
- **THEN** it states the same wildcard, case-insensitivity, and multi-term syntax the Analysis page states

#### Scenario: The viewer's own controls are unaffected
- **WHEN** user changes the per-page row count or triggers Refresh on the Logs page
- **THEN** the page behaves as it does today, showing the newest matching rows for the active filter set

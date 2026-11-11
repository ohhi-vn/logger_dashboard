# Spec Delta

## ADDED Requirements

### Requirement: Wildcard text exclusion

The system SHALL support an `exclude` filter over `message` using the same
wildcard syntax and term combination as search: `*` matches any run of
characters, `?` matches a single character, a term without a wildcard matches
anywhere in the message, matching ignores letter case, and space-separated
terms are combined with AND. A row is removed from the result when its message
matches the exclude pattern. An empty or absent `exclude` SHALL apply no
exclusion predicate.

The exclude predicate SHALL be evaluated by the database and combined with
the search, node, datetime-range, and level predicates.

#### Scenario: Exclude filters out matching rows

- **WHEN** user enters `*health*` in exclude
- **THEN** system returns only rows whose message does not match that pattern

#### Scenario: Empty exclude applies no predicate

- **WHEN** exclude is empty or absent
- **THEN** system applies no exclusion predicate

#### Scenario: Exclude combines with search and other filters

- **WHEN** user enters a search and an exclude together with a node scope,
  datetime range, and level
- **THEN** system applies both the search and the exclude predicates to rows
  already matching that scope, range, and level

#### Scenario: Exclude ignores letter case

- **WHEN** user enters `Health` in exclude and a row's message reads
  `Health check ok`
- **THEN** that row is excluded

#### Scenario: Several exclude terms are combined with AND

- **WHEN** user enters `*health* *ok*` in exclude
- **THEN** system excludes only rows whose message matches both terms

#### Scenario: A term without a wildcard matches anywhere in the message

- **WHEN** user enters `health` in exclude
- **THEN** system excludes rows whose message contains `health`, not only rows
  whose message is exactly `health`

## MODIFIED Requirements

### Requirement: Logs-to-analysis handoff

The system SHALL offer a handoff action on the Logs page that navigates to
`/analysis` carrying the active `node`, `search`, `exclude`, `from`, `to`, and
`level` filters, so the Analysis page opens on the same scope without
retyping. The handoff SHALL preserve every active filter value as typed and
SHALL NOT alter the Logs page filters, page position, or rows shown.

#### Scenario: Handoff carries active filters to analysis

- **WHEN** user triggers the handoff with node, search, exclude,
  datetime-range, and level filters active on the Logs page
- **THEN** the Analysis page opens with those same node, search, exclude,
  datetime-range, and level values applied

#### Scenario: Handoff with no filters opens unscoped analysis

- **WHEN** user triggers the handoff with no filters active on the Logs page
- **THEN** the Analysis page opens in whole-system scope with no search
  keyword and no exclude value

#### Scenario: Handoff does not disturb the Logs page

- **WHEN** user triggers the handoff
- **THEN** the Logs page filters, page position, and rows shown are unchanged

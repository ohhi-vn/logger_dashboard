# Spec Delta

## MODIFIED Requirements

### Requirement: Level frequency breakdown

The system SHALL show count-by-`level` for the active scope and time range, computed over a bounded set of rows, and SHALL disclose that bound alongside the result.

#### Scenario: Frequency by level

- **WHEN** analysis runs for a 24h range
- **THEN** system shows per-level counts (error, warning, info, debug) for the rows it analyzed

#### Scenario: Counts are bounded, not totals

- **WHEN** the rows matching the scope and range exceed the applied analysis bound
- **THEN** system states that the counts were computed from a bounded set of rows and do not present them as the exact totals for the scope and range

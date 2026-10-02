# Spec Delta

## ADDED Requirements

### Requirement: Time-bounded prune by default

The system SHALL reject a prune whose datetime range is unbounded on both ends, and SHALL provide no override that permits an unbounded delete.

#### Scenario: Unbounded prune rejected

- **WHEN** user previews a prune with neither a `from` nor a `to` bound
- **THEN** system rejects it with a validation error and runs no delete

#### Scenario: One-sided range is sufficient

- **WHEN** user previews a prune with only a `from` bound, or only a `to` bound
- **THEN** system accepts it and treats the missing end as open

#### Scenario: Rejection names the remedy

- **WHEN** system rejects an unbounded prune
- **THEN** the error tells the user to supply a datetime range

## MODIFIED Requirements

### Requirement: Prune safety guardrails

The system SHALL reject a prune with no explicit scope selection and SHALL NOT expose prune as a GET/link endpoint. A missing scope parameter SHALL be rejected as an error and SHALL NOT default to whole-system deletion.

#### Scenario: Missing scope rejected

- **WHEN** user submits prune with scope `node` but no node value
- **THEN** system rejects with a validation error and runs no delete

#### Scenario: Absent scope parameter rejected

- **WHEN** a prune request arrives with no scope parameter at all
- **THEN** system rejects with a validation error and deletes nothing, rather than treating the absent scope as whole-system

#### Scenario: Prune requires POST/action

- **WHEN** a prune URL is visited via GET
- **THEN** system performs no delete

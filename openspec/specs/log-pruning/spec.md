# Log Pruning Specification

## Purpose

Lets operators reclaim ClickHouse space by pruning log rows for one node or the whole system under an explicit, confirmed scope.

## Requirements

### Requirement: Scoped prune selection

The system SHALL allow pruning by scope `node` (requires a node value) or `all-nodes`, combined with optional datetime-range and level filters that default to "everything in scope". The prune page SHALL accept `from` and `to` through the same datetime-picker and ISO8601 field affordance the viewer uses, and SHALL offer age-cutoff shortcuts that set only the upper bound: older than 1 day, 3 days, 7 days, 30 days, and 90 days.

#### Scenario: Prune single node

- **WHEN** user chooses scope `node=my_app@10.0.0.5` with range older than
  `2026-08-01T00:00:00Z`
- **THEN** system deletes only rows matching that node and range

#### Scenario: Prune whole system requires explicit scope

- **WHEN** user chooses scope `all-nodes`
- **THEN** system treats it as every node and still requires the same explicit
  confirmation as node prune (no implicit single-node fallback)

#### Scenario: Age shortcut sets only the upper bound

- **WHEN** user selects "older than 7 days" on the prune page
- **THEN** the `to` bound becomes the current time minus 7 days, `from` remains
  unset, and the confirmation text states that cutoff

#### Scenario: Age shortcut does not replace the node scope

- **WHEN** user selects an age shortcut
- **THEN** the selected scope and node value are unchanged

#### Scenario: Age shortcut is editable before it runs

- **WHEN** an age shortcut has set `to` and user then edits `to` directly
- **THEN** system uses the edited `to`, not the shortcut's cutoff

### Requirement: Explicit confirmation before delete

The system SHALL require an explicit confirmation step that states the resolved scope (node/all-nodes, time range, levels) before any delete executes.

#### Scenario: Confirmation shows resolved scope

- **WHEN** user submits a prune request
- **THEN** system shows the resolved predicate (node, time range, levels, estimated or exact match count when cheap) and only deletes after user confirms

#### Scenario: Cancel aborts prune

- **WHEN** user cancels at the confirmation step
- **THEN** system deletes zero rows

### Requirement: Prune outcome reporting

The system SHALL report prune outcome as scope plus affected-row information and surface ClickHouse async-delete semantics.

#### Scenario: Successful prune reports scope

- **WHEN** a confirmed prune completes
- **THEN** system shows scope pruned and rows affected (or "delete dispatched, ClickHouse applies asynchronously" when exact count is unavailable) and the viewer no longer returns pruned rows once the mutation applies

#### Scenario: Failed prune surfaces error

- **WHEN** the ClickHouse delete fails
- **THEN** system shows an error naming the scope and the failure reason and deletes nothing silently

### Requirement: Time-bounded prune by default

The system SHALL reject a prune whose datetime range is unbounded on both ends, and SHALL provide no override that permits an unbounded delete. A selected age-cutoff shortcut SHALL count as supplying the bound it sets, and SHALL leave the other end open.

#### Scenario: Unbounded prune rejected

- **WHEN** user previews a prune with neither a `from` nor a `to` bound
- **THEN** system rejects it with a validation error and runs no delete

#### Scenario: One-sided range is sufficient

- **WHEN** user previews a prune with only a `from` bound, or only a `to` bound
- **THEN** system accepts it and treats the missing end as open

#### Scenario: Rejection names the remedy

- **WHEN** system rejects an unbounded prune
- **THEN** the error tells the user to supply a datetime range

#### Scenario: An age shortcut satisfies the bound requirement

- **WHEN** user previews a prune after selecting an age shortcut and has not
  cleared `to`
- **THEN** system accepts the prune as bounded and proceeds only to the
  confirmation step

#### Scenario: Clearing the shortcut's bound restores the rejection

- **WHEN** user selects an age shortcut and then clears `to`
- **THEN** system rejects the prune as unbounded and runs no delete

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

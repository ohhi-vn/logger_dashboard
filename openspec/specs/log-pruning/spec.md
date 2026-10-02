# Log Pruning Specification

## Purpose

Lets operators reclaim ClickHouse space by pruning log rows for one node or the whole system under an explicit, confirmed scope.

## Requirements

### Requirement: Scoped prune selection

The system SHALL allow pruning by scope `node` (requires a node value) or `all-nodes`, combined with optional datetime-range and level filters that default to "everything in scope".

#### Scenario: Prune single node

- **WHEN** user chooses scope `node=my_app@10.0.0.5` with range older than `2026-08-01T00:00:00Z`
- **THEN** system deletes only rows matching that node and range

#### Scenario: Prune whole system requires explicit scope

- **WHEN** user chooses scope `all-nodes`
- **THEN** system treats it as every node and still requires the same explicit confirmation as node prune (no implicit single-node fallback)

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

### Requirement: Prune safety guardrails

The system SHALL reject a prune with no explicit scope selection and SHALL NOT expose prune as a GET/link endpoint.

#### Scenario: Missing scope rejected

- **WHEN** user submits prune with scope `node` but no node value
- **THEN** system rejects with a validation error and runs no delete

#### Scenario: Prune requires POST/action

- **WHEN** a prune URL is visited via GET
- **THEN** system performs no delete

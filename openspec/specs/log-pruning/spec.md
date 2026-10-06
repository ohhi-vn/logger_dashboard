# Log Pruning Specification

## Purpose

Lets operators reclaim ClickHouse space by pruning log rows for one node or the whole system under an explicit, confirmed scope.

## Requirements

### Requirement: Scoped prune selection

The system SHALL allow pruning by scope `node` (requires a node value) or `all-nodes`, combined with optional datetime-range and level filters that default to "everything in scope". The prune page SHALL accept `from` and `to` through the same datetime-picker and ISO8601 field affordance the viewer uses, and SHALL offer age-cutoff shortcuts that set only the upper bound, ordered shortest first: older than 1 hour, 6 hours, 12 hours, 1 day, 3 days, 7 days, 30 days, and 90 days.

These shortcuts SHALL be drawn from the same relative-cutoff vocabulary the scheduled retention policy uses, so that an age cutoff can be expressed in hours on the prune page as well as in days, and the same named duration means the same cutoff on both surfaces.

The prune page SHALL present the known nodes as clickable options alongside the node input. Clicking a node option SHALL select the single-node scope for that node, replacing any previously entered node value, without disturbing the datetime range or level. The prune page SHALL present each level as a clickable option, and clicking an option SHALL select that level.

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

#### Scenario: Hour-valued age shortcuts are offered

- **WHEN** user views the age-cutoff shortcuts on the prune page
- **THEN** the offered shortcuts include durations expressed in hours as well as in
  days

#### Scenario: Age shortcuts are ordered shortest first

- **WHEN** user views the age-cutoff shortcuts on the prune page
- **THEN** they are presented shortest duration first

#### Scenario: A named duration means the same cutoff on both surfaces

- **WHEN** the same named duration is applied as a manual age cutoff on the prune
  page and as the retained age of a scheduled retention policy
- **THEN** both resolve to the same cutoff relative to the instant they are applied

#### Scenario: Age shortcut does not replace the node scope

- **WHEN** user selects an age shortcut
- **THEN** the selected scope and node value are unchanged

#### Scenario: Age shortcut is editable before it runs

- **WHEN** an age shortcut has set `to` and user then edits `to` directly
- **THEN** system uses the edited `to`, not the shortcut's cutoff

#### Scenario: Clicking a node option selects the single-node scope

- **WHEN** user clicks a node option on the prune page
- **THEN** the scope becomes `node` for that value, replacing any previously entered node, while the datetime range and level stay unchanged

#### Scenario: Clicking a node option still requires confirmation

- **WHEN** user clicks a node option on the prune page
- **THEN** system selects the scope but deletes nothing until the preview is confirmed

#### Scenario: Clicking a level selects it for prune

- **WHEN** user clicks the `error` level option on the prune page
- **THEN** the level becomes `error` while the scope and datetime range stay unchanged

### Requirement: Explicit confirmation before delete

The system SHALL require an explicit confirmation step that states the resolved scope (node/all-nodes, time range, levels) before any delete executes. The confirmation SHALL include the number of rows matching the resolved scope and a bounded sample of the newest matching rows, both computed from the same validated filter the delete will execute. The sample SHALL be bounded to a small fixed size and SHALL render each sampled row with its UTC `timestamp`, `level`, `node`, untruncated `message`, and source location when present. A scope that matches no rows SHALL state a zero count and offer no sample rows, and confirming it SHALL still require the explicit confirm action. Any change to the prune params SHALL clear the pending preview so a stale count or sample can never be confirmed for a different scope.

#### Scenario: Confirmation shows resolved scope

- **WHEN** user submits a prune request
- **THEN** system shows the resolved predicate (node, time range, levels, estimated or exact match count when cheap) and only deletes after user confirms

#### Scenario: Preview shows matching-row count

- **WHEN** user previews a prune whose scope matches N rows
- **THEN** the confirmation states N as the number of rows that will be deleted

#### Scenario: Preview shows bounded newest-rows sample

- **WHEN** user previews a prune whose scope matches rows
- **THEN** the confirmation shows a bounded sample of the newest matching rows with timestamp, level, node, message, and source location

#### Scenario: Preview of empty scope states zero with no sample

- **WHEN** user previews a prune whose scope matches no rows
- **THEN** the confirmation states zero matching rows and shows no sample rows

#### Scenario: Preview count comes from the filter the delete executes

- **WHEN** user confirms a previewed prune
- **THEN** the delete executes the same validated node, time-range, and level predicates the preview counted

#### Scenario: Changing params clears the preview

- **WHEN** user changes scope, node, datetime range, level, or shortcut after a preview is shown
- **THEN** the pending preview (count and sample) is cleared and confirming requires a fresh preview

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

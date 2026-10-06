# Spec Delta

## MODIFIED Requirements

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

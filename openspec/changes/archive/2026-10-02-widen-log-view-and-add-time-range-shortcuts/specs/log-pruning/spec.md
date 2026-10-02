# Spec Delta

## MODIFIED Requirements

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

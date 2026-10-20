# Spec Delta

## MODIFIED Requirements

### Requirement: Scoped prune selection

The system SHALL allow pruning by scope `node` (requires a node value) or `all-nodes`, combined with optional datetime-range and level filters that default to "everything in scope". The prune page SHALL open in `all-nodes` scope by default when no scope param is present. The prune page SHALL offer no scope selector control: clicking a node badge selects the single-node scope and the select-all action selects whole-system scope, and the scope so chosen SHALL travel in the request params exactly as the removed selector sent it. The prune page SHALL accept `from` and `to` through the same datetime-picker and ISO8601 field affordance the viewer uses, and SHALL offer age-cutoff shortcuts that set only the upper bound, ordered shortest first: older than 1 hour, 6 hours, 12 hours, 1 day, 3 days, 7 days, 30 days, and 90 days, plus an `All time` shortcut that clears both bounds and marks the scope as explicitly unbounded.

These shortcuts SHALL be drawn from the same relative-cutoff vocabulary the scheduled retention policy uses, so that an age cutoff can be expressed in hours on the prune page as well as in days, and the same named duration means the same cutoff on both surfaces.

The prune page SHALL present the known nodes only as clickable badge options with no free-text node input, plus a select-all action returning to whole-system scope. Clicking a node option SHALL select the single-node scope for that node without disturbing the datetime range or level. The prune page SHALL present each level as a clickable option, and clicking an option SHALL select that level. The prune page SHALL offer no prune-all button. Choosing a scope, a cutoff, or a level SHALL only change what the page would delete: it SHALL recompute the read-only review and SHALL delete nothing.

#### Scenario: Prune single node
- **WHEN** user chooses scope `node=my_app@10.0.0.5` with range older than `2026-08-01T00:00:00Z`
- **THEN** system deletes only rows matching that node and range

#### Scenario: Prune whole system requires explicit scope
- **WHEN** user chooses scope `all-nodes`
- **THEN** system treats it as every node and still requires the same explicit confirmation as node prune (no implicit single-node fallback)

#### Scenario: Prune page opens in whole-system scope
- **WHEN** user opens `/prune` with no scope param
- **THEN** the page shows `all-nodes` scope selected and no node value

#### Scenario: No scope selector is offered
- **WHEN** user views the prune filter
- **THEN** no single-node/whole-system select control is present; scope changes only through the node badges or select-all

#### Scenario: Age shortcut sets only the upper bound
- **WHEN** user selects "older than 7 days" on the prune page
- **THEN** the `to` bound becomes the current time minus 7 days, `from` remains unset, and the confirmation text states that cutoff

#### Scenario: Hour-valued age shortcuts are offered
- **WHEN** user views the age-cutoff shortcuts on the prune page
- **THEN** the offered shortcuts include durations expressed in hours as well as in days

#### Scenario: Age shortcuts are ordered shortest first
- **WHEN** user views the age-cutoff shortcuts on the prune page
- **THEN** they are presented shortest duration first

#### Scenario: A named duration means the same cutoff on both surfaces
- **WHEN** the same named duration is applied as a manual age cutoff on the prune page and as the retained age of a scheduled retention policy
- **THEN** both resolve to the same cutoff relative to the instant they are applied

#### Scenario: Age shortcut does not replace the node scope
- **WHEN** user selects an age shortcut
- **THEN** the selected scope and node value are unchanged

#### Scenario: Age shortcut is editable before it runs
- **WHEN** an age shortcut has set `to` and user then edits `to` directly
- **THEN** system uses the edited `to`, not the shortcut's cutoff

#### Scenario: Clicking a node option selects the single-node scope
- **WHEN** user clicks a node option on the prune page
- **THEN** the scope becomes `node` for that value while the datetime range and level stay unchanged

#### Scenario: Clicking a node option still requires confirmation
- **WHEN** user clicks a node option on the prune page
- **THEN** system selects the scope, recomputes the read-only review, and deletes nothing until the operator confirms

#### Scenario: Select-all returns prune to whole-system scope
- **WHEN** user triggers select-all on the prune page
- **THEN** the scope becomes `all-nodes` while the datetime range and level stay unchanged, and nothing is deleted until the operator confirms

#### Scenario: No free-text node input is offered on prune
- **WHEN** user views the prune filter
- **THEN** no single-node text field is present; node scope changes only through the badge options or select-all

#### Scenario: All time clears both bounds and marks the scope unbounded
- **WHEN** user selects `All time` on the prune page
- **THEN** both `from` and `to` are cleared, the scope stays unchanged, and no delete runs

#### Scenario: All time does not replace the node scope
- **WHEN** user selects `All time`
- **THEN** the selected scope and node value are unchanged

#### Scenario: No prune-all button is offered
- **WHEN** user views the prune filter
- **THEN** no prune-all shortcut is present

#### Scenario: Clicking a level selects it for prune
- **WHEN** user clicks the `error` level option on the prune page
- **THEN** the level becomes `error` while the scope and datetime range stay unchanged

### Requirement: Explicit confirmation before delete

The system SHALL require an explicit confirmation step that states the resolved scope (node/all-nodes, time range, levels) before any delete executes. The confirmation SHALL include the number of rows matching the resolved scope and a bounded sample of the newest matching rows, both computed from the same validated filter the delete will execute. The sample SHALL be bounded to a small fixed size and SHALL render each sampled row with its UTC `timestamp`, `level`, `node`, untruncated `message`, and source location when present. A scope that matches no rows SHALL state a zero count and offer no sample rows, and confirming it SHALL still require the explicit confirm action. The count and sample on screen SHALL always describe the scope currently in effect: the system SHALL recompute them whenever the scope, the range, the level, or the cutoff changes, and SHALL never offer a confirm action against a count or sample computed for a different scope.

The confirmation SHALL use the shell's shared visual language, and the destructive confirm action SHALL be visually unmistakable as destructive (not styled like a neutral primary action). Validation errors SHALL name the rejected field in text and SHALL NOT rely on color alone, and every control on the page SHALL show a visible keyboard-focus indicator.

#### Scenario: Confirmation shows resolved scope

- **WHEN** user submits a prune request
- **THEN** system shows the resolved predicate (node, time range, levels, estimated or exact match count when cheap) and only deletes after user confirms

#### Scenario: Preview shows matching-row count

- **WHEN** the review is shown for a scope that matches N rows
- **THEN** the confirmation states N as the number of rows that will be deleted

#### Scenario: Preview shows bounded newest-rows sample

- **WHEN** the review is shown for a scope that matches rows
- **THEN** the confirmation shows a bounded sample of the newest matching rows with timestamp, level, node, message, and source location

#### Scenario: Preview of empty scope states zero with no sample

- **WHEN** the review is shown for a scope that matches no rows
- **THEN** the confirmation states zero matching rows and shows no sample rows

#### Scenario: Preview count comes from the filter the delete executes

- **WHEN** user confirms a reviewed prune
- **THEN** the delete executes the same validated node, time-range, and level predicates the review counted

#### Scenario: Changing params clears the preview

- **WHEN** user changes scope, node, datetime range, level, or shortcut after a review is shown
- **THEN** the previous scope's count and sample are cleared and recomputed for the new scope, so the review on screen never describes a scope other than the one in effect

#### Scenario: A stale review can never be confirmed

- **WHEN** the scope changes and the recomputed review has not yet been shown
- **THEN** no confirm action acts on the previous scope's count or sample

#### Scenario: Cancel aborts prune

- **WHEN** user cancels at the confirmation step
- **THEN** system deletes zero rows

#### Scenario: The confirm action reads as destructive

- **WHEN** the confirmation step is shown
- **THEN** the confirm action is styled as destructive and is visually distinct from neutral actions, so it cannot be mistaken for a harmless submit

#### Scenario: Prune errors name the field in text

- **WHEN** user submits a prune the system rejects
- **THEN** the error names the rejected field in text rather than relying on color alone

### Requirement: Prune filter refreshes without destructive auto-run

The system SHALL keep prune filter controls consistent with the viewer badge model while auto-updating only the read-only review state, never dispatching a delete automatically. A change to the scope, the range, the level, or the cutoff SHALL recompute the review from the new scope, and a separate refresh action SHALL NOT be required for the page to show what the current scope would delete.

#### Scenario: Toggling a prune control never deletes

- **WHEN** user toggles a node badge, level option, age shortcut, or picker value on the prune page
- **THEN** the page updates its filter state, recomputes the review for the new scope, and dispatches no delete

#### Scenario: Refresh re-resolves the prune scope without previewing

- **WHEN** user triggers Refresh on the prune page
- **THEN** the page re-resolves the current scope, range, and level into visible state, recomputes the read-only review, and dispatches no delete

#### Scenario: Absent scope param is still rejected

- **WHEN** a prune request arrives with no scope parameter at all
- **THEN** system rejects it with a validation error and deletes nothing, rather than treating the absent scope as whole-system

## ADDED Requirements

### Requirement: Guided prune flow

The prune page SHALL present the operation as ordered steps — choose the scope, set the cutoff, review what would be deleted, confirm — and SHALL show which step the operator is on. The scope, level, cutoff, and the actions that act on them SHALL be presented together in a single filter card rather than in controls scattered above and below the form. The steps SHALL NOT gate the operation: the confirm action SHALL be reachable from any step.

#### Scenario: The page names the steps
- **WHEN** user opens the prune page
- **THEN** the page shows the scope, cutoff, review, and confirm steps in that order

#### Scenario: The current step is marked
- **WHEN** the page shows the steps
- **THEN** the step the operator is on is marked as current

#### Scenario: The scope, level, cutoff, and actions share one card
- **WHEN** user views the prune page
- **THEN** the node options, the level options, the datetime bounds, the cutoff shortcuts, and the prune actions are all presented within one filter card

#### Scenario: The steps add no extra clicks before confirming
- **WHEN** user has chosen a scope and a cutoff
- **THEN** the confirm action is reachable without pressing a separate "next step" action, and the delete still happens only on that confirm

### Requirement: Live blast-radius review

The prune page SHALL recompute the review — the rows that would be deleted, their distribution across nodes, and a sample of them — from the current scope and filters without requiring a separate preview action, and SHALL show it before a delete can be confirmed. A review that cannot be computed SHALL block the confirm action and report the failure, because a destructive confirmation must not understate its scope.

#### Scenario: The review updates as the scope changes
- **WHEN** user changes the node scope
- **THEN** the review shows the row count and sample for the new scope

#### Scenario: The review updates as the cutoff or level changes
- **WHEN** user changes the cutoff, the bounds, or the level
- **THEN** the review shows the row count and sample for the new filter set

#### Scenario: No separate preview action is required
- **WHEN** user views the prune page
- **THEN** no separate "preview" submit stands between the filters and the review

#### Scenario: A failed review read blocks the confirm
- **WHEN** the review cannot be computed
- **THEN** the page reports the failure and offers no confirm action, and deletes nothing

### Requirement: Review states the affected scope in detail

The review SHALL state the scope it describes in concrete terms: the node or the whole-system scope, the resolved UTC cutoffs, the level scope, the number of rows that would be deleted, and how those rows are distributed across nodes. A scope with no cutoff SHALL say so explicitly rather than presenting itself as bounded.

#### Scenario: The review names the resolved UTC cutoffs
- **WHEN** the review is shown for a scope with a cutoff
- **THEN** it states the resolved `from` and `to` instants in UTC

#### Scenario: An unbounded scope says so explicitly
- **WHEN** the review is shown for a scope carrying the `All time` mark
- **THEN** it states that every row in scope would be deleted, with no time bound

#### Scenario: The review names the level scope
- **WHEN** the review is shown for a scope limited to a level
- **THEN** it states that level

#### Scenario: The review shows the per-node row counts
- **WHEN** the review is shown for a whole-system scope
- **THEN** it states how many of the rows that would be deleted belong to each node

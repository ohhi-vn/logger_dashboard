# Spec Delta

## MODIFIED Requirements

### Requirement: Scoped prune selection
The system SHALL allow pruning by scope `node` (requires a node value) or `all-nodes`, combined with optional datetime-range and level filters that default to "everything in scope". The prune page SHALL open in `all-nodes` scope by default when no scope param is present. The prune page SHALL offer no scope selector control: clicking a node badge selects the single-node scope and the select-all action selects whole-system scope, and the scope so chosen SHALL travel in the request params exactly as the removed selector sent it. The prune page SHALL accept `from` and `to` through the same datetime-picker and ISO8601 field affordance the viewer uses, and SHALL offer age-cutoff shortcuts that set only the upper bound, ordered shortest first: older than 1 hour, 6 hours, 12 hours, 1 day, 3 days, 7 days, 30 days, and 90 days, plus an `All time` shortcut that clears both bounds and marks the scope as explicitly unbounded.

These shortcuts SHALL be drawn from the same relative-cutoff vocabulary the scheduled retention policy uses, so that an age cutoff can be expressed in hours on the prune page as well as in days, and the same named duration means the same cutoff on both surfaces.

The prune page SHALL present the known nodes only as clickable badge options with no free-text node input, plus a select-all action returning to whole-system scope. Clicking a node option SHALL select the single-node scope for that node without disturbing the datetime range or level. The prune page SHALL present each level as a clickable option, and clicking an option SHALL select that level. The prune page SHALL offer no prune-all button.

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
- **THEN** system selects the scope but deletes nothing until the preview is confirmed

#### Scenario: Select-all returns prune to whole-system scope
- **WHEN** user triggers select-all on the prune page
- **THEN** the scope becomes `all-nodes` while the datetime range and level stay unchanged, and nothing is deleted until previewed and confirmed

#### Scenario: No free-text node input is offered on prune
- **WHEN** user views the prune filter
- **THEN** no single-node text field is present; node scope changes only through the badge options or select-all

#### Scenario: All time clears both bounds and marks the scope unbounded
- **WHEN** user selects `All time` on the prune page
- **THEN** both `from` and `to` are cleared, the scope stays unchanged, and no preview, confirmation, or delete runs

#### Scenario: All time does not replace the node scope
- **WHEN** user selects `All time`
- **THEN** the selected scope and node value are unchanged

#### Scenario: No prune-all button is offered
- **WHEN** user views the prune filter
- **THEN** no prune-all shortcut is present

#### Scenario: Clicking a level selects it for prune
- **WHEN** user clicks the `error` level option on the prune page
- **THEN** the level becomes `error` while the scope and datetime range stay unchanged

### Requirement: Time-bounded prune by default
The system SHALL reject a prune whose datetime range is unbounded on both ends, unless the `All time` shortcut marks the scope as explicitly unbounded — that mark is the only override that permits an unbounded delete. A selected age-cutoff shortcut SHALL count as supplying the bound it sets, and SHALL leave the other end open.

#### Scenario: Unbounded prune rejected
- **WHEN** user previews a prune with neither a `from` nor a `to` bound and without the `All time` mark
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

#### Scenario: All time permits an explicitly unbounded preview
- **WHEN** user previews a prune whose scope carries the `All time` mark with no bounds set
- **THEN** system proceeds to the confirmation step stating that every row in scope will be deleted, rather than rejecting it as unbounded

#### Scenario: Manually cleared bounds without All time stay rejected
- **WHEN** user clears both bounds by hand without selecting `All time`
- **THEN** system rejects the preview as unbounded and runs no delete

#### Scenario: Typing a bound after All time makes it bounded again
- **WHEN** user selects `All time` and then types a `from` or `to` bound
- **THEN** system treats the preview as bounded by the typed value rather than as explicitly unbounded

## ADDED Requirements

### Requirement: Prune filter refreshes without destructive auto-run
The system SHALL keep prune filter controls consistent with the viewer badge model while auto-updating only the pending preview state, never dispatching preview or delete automatically. A Refresh action re-resolves the current scope.

#### Scenario: Toggling a prune control never deletes
- **WHEN** user toggles a node badge, level option, age shortcut, or picker value on the prune page
- **THEN** the page updates its filter state and clears any stale preview, and dispatches no preview and no delete

#### Scenario: Refresh re-resolves the prune scope without previewing
- **WHEN** user triggers Refresh on the prune page
- **THEN** the page re-resolves the current scope, range, and level into visible state with no delete dispatched

#### Scenario: Absent scope param is still rejected
- **WHEN** a prune request arrives with no scope parameter at all
- **THEN** system rejects with a validation error and deletes nothing, rather than treating the absent scope as whole-system

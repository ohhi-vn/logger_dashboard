# Spec Delta

## MODIFIED Requirements

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

# Spec Delta

## ADDED Requirements

### Requirement: Level filter layout

The system SHALL render exactly one level selector on the Logs page, consisting of the clickable level toggle options plus the `all` reset option, placed inside the filter card as its own full-width row. The level row SHALL NOT overlap, clip, or cover the node, search, datetime-range, per-page, or action controls at any viewport width. The filter card grid SHALL wrap cleanly: inputs occupy their own grid cells on wide screens and stack vertically without overlap on narrow screens.

#### Scenario: Single level control inside the filter card
- **WHEN** user opens the Logs page
- **THEN** the page shows exactly one level selector (toggle options plus `all`) and it sits inside the filter card on its own row

#### Scenario: Level selector does not overlap other controls on desktop
- **WHEN** user views the Logs page filter card on a wide viewport
- **THEN** the level row, node input, search input, datetime inputs, per-page select, and action buttons each occupy distinct non-overlapping areas

#### Scenario: Level selector does not overlap other controls on narrow screens
- **WHEN** user views the Logs page filter card on a narrow viewport
- **THEN** the level row and every other filter input stack vertically with no overlap or clipping

#### Scenario: Level toggle behaviour is unchanged
- **WHEN** user clicks a level option on the redesigned Logs filter
- **THEN** the system toggles that level in or out of the active set without disturbing the other active filters, exactly as before

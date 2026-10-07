# Spec Delta

## ADDED Requirements

### Requirement: Analysis level filter layout

The system SHALL render exactly one level selector on the Analysis page, consisting of the clickable level toggle options plus the `all` reset option, placed inside the filter card as its own full-width row. The level row SHALL NOT overlap, clip, or cover the node, search, datetime-range, bucket, or action controls at any viewport width. The filter card grid SHALL wrap cleanly: inputs occupy their own grid cells on wide screens and stack vertically without overlap on narrow screens.

#### Scenario: Single level control inside the analysis filter card
- **WHEN** user opens the Analysis page
- **THEN** the page shows exactly one level selector (toggle options plus `all`) and it sits inside the filter card on its own row

#### Scenario: Analysis level selector does not overlap other controls on desktop
- **WHEN** user views the Analysis page filter card on a wide viewport
- **THEN** the level row, node input, search input, datetime inputs, bucket select, and action buttons each occupy distinct non-overlapping areas

#### Scenario: Analysis level selector does not overlap other controls on narrow screens
- **WHEN** user views the Analysis page filter card on a narrow viewport
- **THEN** the level row and every other filter input stack vertically with no overlap or clipping

#### Scenario: Analysis level toggle behaviour is unchanged
- **WHEN** user clicks a level option on the redesigned Analysis filter
- **THEN** the system toggles that level in or out of the active set without disturbing node, range, search, or bucket, exactly as before

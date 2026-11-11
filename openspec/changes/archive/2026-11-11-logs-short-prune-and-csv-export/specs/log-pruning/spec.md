# Spec Delta

## ADDED Requirements

### Requirement: Prune initiated from the Logs page

The system SHALL permit a prune to be initiated from the Logs page using the
viewer's current filter, in addition to the dedicated `/prune` page. Such a
prune SHALL be subject to the same scope, bounds, review, confirmation, and
outcome-reporting rules as a prune initiated from `/prune`, and SHALL reuse
the same validated predicates and review data. It SHALL NOT delete on GET or
without an explicit confirm action.

#### Scenario: A Logs-page prune follows the same safety rules

- **WHEN** a prune is initiated from the Logs page
- **THEN** it requires a valid scope and bounds, shows a review, and deletes
  only after explicit confirmation

#### Scenario: A Logs-page prune uses the current filter

- **WHEN** a prune is initiated from the Logs page
- **THEN** it targets the rows matching the viewer's current node, time, and
  level filters

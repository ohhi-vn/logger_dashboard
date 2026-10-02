# Spec Delta

## MODIFIED Requirements

### Requirement: Consistent page shell

The system SHALL render every dashboard page inside the shared shell, which provides the navigation, flash messages, and a consistent responsive content container. The content container SHALL span the viewport on wide screens so wide content such as log lines is not squeezed into a fixed measure, and SHALL retain horizontal padding and stay within the viewport on narrow screens. Exactly one container SHALL govern content width: no page SHALL impose a second width cap of its own inside the shell.

#### Scenario: Every page uses the shell

- **WHEN** any dashboard page renders
- **THEN** the shared navigation and flash group are present

#### Scenario: Content uses the full viewport width

- **WHEN** any dashboard page renders on a screen wider than the shell's
  horizontal padding
- **THEN** its content container extends to the shell's padding edges rather
  than stopping at a narrower fixed width

#### Scenario: Content stays inside the viewport on narrow screens

- **WHEN** any dashboard page renders on a narrow screen
- **THEN** its content does not overflow horizontally

#### Scenario: One container governs width on every page

- **WHEN** user views the homepage, Logs, Analysis, or Prune
- **THEN** each page's content is governed by the same container, with no page
  narrowing it further

# Spec Delta

## MODIFIED Requirements

### Requirement: Consistent page shell

The system SHALL render every dashboard page inside the shared shell, which provides the navigation, flash messages, and a consistent responsive content container. The content container SHALL span the viewport on wide screens so wide content such as log lines is not squeezed into a fixed measure, and SHALL retain horizontal padding and stay within the viewport on narrow screens. Exactly one container SHALL govern content width: no page SHALL impose a second width cap of its own inside the shell.

The shell SHALL give every page the same visual language for repeated elements: page titles with a short description, filter sections presented as cards with labeled inputs and primary/ghost actions in the same order, tables with the same header/body density, and flash messages in the same position and style. Every interactive control SHALL show a visible keyboard-focus indicator, and no control SHALL remove the focus outline without replacing it with an equally visible one. Body text SHALL meet WCAG AA contrast (4.5:1) against its background in every theme the shell offers.

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

#### Scenario: Repeated elements share one visual language

- **WHEN** user views the homepage, Logs, Analysis, or Prune
- **THEN** page titles, filter cards, tables, buttons, and flash messages use
  the same styling on every page, so a control learned on one page is
  recognizable on the others

#### Scenario: Keyboard focus is always visible

- **WHEN** user tabs through the navigation, filter controls, and actions on
  any dashboard page
- **THEN** each focused control shows a visible focus indicator

#### Scenario: Body text meets AA contrast in every theme

- **WHEN** any dashboard page renders in any offered theme
- **THEN** body text contrast against its background meets WCAG AA (4.5:1)

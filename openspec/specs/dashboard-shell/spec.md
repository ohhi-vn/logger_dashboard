# Dashboard Shell Specification

## Purpose

Gives the dashboard a real entry point and a consistent navigation frame so operators can move between viewing, analyzing, and pruning logs without typing URLs.

## Requirements

### Requirement: Dashboard homepage

The system SHALL serve a dashboard homepage at `/` that identifies the application and links to each tool: Logs, Analysis, and Prune. It SHALL NOT show the Phoenix framework marketing content.

#### Scenario: Homepage lists every tool

- **WHEN** user visits `/`
- **THEN** the page contains links to `/logs`, `/analysis`, and `/prune`

#### Scenario: Homepage replaces the boilerplate

- **WHEN** user visits `/`
- **THEN** the page does not show Phoenix framework marketing copy

### Requirement: Cross-page navigation

The system SHALL render a persistent navigation affordance on every dashboard page that links to the homepage and to each tool, and SHALL mark the current page as active.

#### Scenario: Navigation present on every page

- **WHEN** user views the homepage, Logs, Analysis, or Prune
- **THEN** links to the homepage and to Logs, Analysis, and Prune are present

#### Scenario: Current page is marked

- **WHEN** user is on a tool page
- **THEN** the navigation marks that tool as the active page in a way assistive technology can detect

#### Scenario: Theme toggle remains available

- **WHEN** user views any page
- **THEN** the light/dark/system theme toggle is available

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

### Requirement: The shell offers a way to end the session

The system SHALL render a sign-out control in the navigation frame on every
authenticated dashboard page. The control SHALL be reachable by keyboard and exposed to
assistive technology with a name that says it ends the session.

The control SHALL NOT appear on the token page, which is not an authenticated dashboard
page and has no session to end.

#### Scenario: Sign-out is available on every page

- **WHEN** user views the homepage, Logs, Analysis, or Prune while authenticated
- **THEN** a sign-out control is present in the navigation frame

#### Scenario: The control is identifiable to assistive technology

- **WHEN** a screen reader reaches the sign-out control
- **THEN** it is named as ending the session rather than only its position or icon

#### Scenario: The control is absent from the token page

- **WHEN** the token page renders
- **THEN** no sign-out control is present, because there is no session to end

# Spec Delta

## Purpose

Gives the dashboard a real entry point and a consistent navigation frame so operators can move between viewing, analyzing, and pruning logs without typing URLs.

## ADDED Requirements

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

The system SHALL render every dashboard page inside the shared shell, which provides the navigation, flash messages, and a consistent responsive content container.

#### Scenario: Every page uses the shell

- **WHEN** any dashboard page renders
- **THEN** the shared navigation and flash group are present

# Spec Delta

## ADDED Requirements

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
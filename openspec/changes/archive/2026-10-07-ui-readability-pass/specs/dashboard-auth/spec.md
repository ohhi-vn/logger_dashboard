# Spec Delta

## MODIFIED Requirements

### Requirement: The token page accepts a token and starts a session

The system SHALL provide a token page containing a single password field and a submit
control. Submitting the current valid token SHALL establish an authenticated session,
SHALL NOT render the submitted value back into the page, and SHALL return the operator
to the page they were trying to reach.

Submitting a token that is not the current valid token SHALL leave the requester
unauthenticated, SHALL re-render the token page with an error, and SHALL delete no rows
and arm no background work.

The token page SHALL be reachable without an authenticated session, and SHALL be
protected against cross-site request forgery in the same way as every other form in the
dashboard.

The token page SHALL use the shell's shared visual language for its card, input,
button, and error styling. The rejection error SHALL name the problem in text and SHALL
NOT rely on color alone, and the field and submit control SHALL show a visible
keyboard-focus indicator.

#### Scenario: A valid token starts a session and returns the operator

- **WHEN** an unauthenticated user is redirected from `/logs` to the token page and
  submits the current valid token
- **THEN** they are returned to `/logs` and served the page without being asked again

#### Scenario: A wrong token is rejected without starting a session

- **WHEN** a user submits a token that is not the current valid token
- **THEN** the token page is re-rendered with an error, no session is established, and
  no dashboard content is shown

#### Scenario: The token page is reachable when unauthenticated

- **WHEN** an unauthenticated request reaches the token page directly
- **THEN** the page is rendered with the token form and no dashboard content

#### Scenario: The token page matches the dashboard form language

- **WHEN** user views the token page
- **THEN** its card, input, button, and error use the shell's shared styling, so it
  reads as part of the same product rather than a one-off page

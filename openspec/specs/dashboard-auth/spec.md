# Dashboard Auth Specification

## Purpose

Single shared-token gate in front of the dashboard so the destructive log browser and prune actions are no longer openly accessible, while staying operable via env or boot-generated tokens.

## Requirements

### Requirement: Token gate on dashboard routes

The system SHALL require a valid token for every dashboard route (`/`, `/logs`,
`/analysis`, `/prune`, and `/dev/*` when enabled). An unauthenticated request that
accepts HTML SHALL be redirected to a token page and SHALL NOT render any dashboard
content. An unauthenticated request that does not accept HTML SHALL be answered `401`
with no body identifying whether the requested path exists.

The system SHALL NOT request credentials through an `Authorization` header, and SHALL
NOT send a `WWW-Authenticate` challenge. Neither HTTP Basic nor
`Authorization: Bearer` SHALL authenticate a request. A credential presented in an
`Authorization` header SHALL be ignored rather than honoured.

#### Scenario: Unauthenticated browser is asked for token

- **WHEN** an unauthenticated user visits `/logs`
- **THEN** the system redirects them to the token page and does not render log data

#### Scenario: Unauthenticated non-browser client is refused without HTML

- **WHEN** a request that does not accept HTML visits a gated route without a session
- **THEN** the system responds `401` and does not return a login page or dashboard data

#### Scenario: No challenge header is sent

- **WHEN** an unauthenticated request is refused
- **THEN** the response carries no `WWW-Authenticate` header

#### Scenario: A token in an Authorization header does not authenticate

- **WHEN** a request presents the current valid token as HTTP Basic credentials or as
  `Authorization: Bearer`
- **THEN** the request is treated as unauthenticated

#### Scenario: Valid token grants access

- **WHEN** a request carries a session established with the current valid token
- **THEN** the system serves the requested dashboard page normally

#### Scenario: Invalid token is rejected without oracle

- **WHEN** a token is submitted to the token page and it is not the current valid token
- **THEN** the system reports the same failure it would report for any other rejected
  token, without indicating whether the token exists or which path was requested

#### Scenario: LiveView sessions are gated

- **WHEN** a LiveView at `/logs`, `/analysis`, or `/prune` mounts or handles events over
  the socket
- **THEN** the system enforces the same token gate, so a socket opened without a valid
  session is sent to the token page rather than mounting

### Requirement: Predefined token via environment

The system SHALL accept a predefined shared token from `DASHBOARD_AUTH_TOKEN` (read in `config/runtime.exs`), with empty/unset treated as absent rather than as an empty-string token.

#### Scenario: Env token is honored

- **WHEN** `DASHBOARD_AUTH_TOKEN` is set to a non-empty value at boot
- **THEN** only that value authenticates until restart or env change

#### Scenario: Empty env does not create empty token

- **WHEN** `DASHBOARD_AUTH_TOKEN` is unset or empty
- **THEN** the system does not accept an empty token and instead falls back to runtime generation

### Requirement: Boot-generated ephemeral token

The system SHALL, when no predefined token is configured, generate a high-entropy token at boot using Elixir/OTP built-ins (`:crypto.strong_rand_bytes/1` plus URL-safe Base encoding), hold it in memory only, and print it once to stdout/log at startup so a container operator can retrieve it via `podman logs`.

#### Scenario: Ephemeral token is generated and surfaced

- **WHEN** the app boots with no `DASHBOARD_AUTH_TOKEN`
- **THEN** it generates a token of at least 128 bits of entropy, stores it only in memory, and logs it once at startup without logging it on subsequent requests

#### Scenario: Ephemeral token rotates on restart

- **WHEN** the app or container restarts without a predefined token
- **THEN** the previous generated token stops working and only the newly generated value authenticates

### Requirement: Constant-time verification and secret hygiene

The system SHALL compare a submitted token with the expected token using a
constant-time comparison, SHALL NOT log token values, and SHALL NOT reflect either
token in a response body, a rendered page, or a flash message.

#### Scenario: Timing-safe compare

- **WHEN** an attacker probes with varying prefixes of the real token
- **THEN** rejection timing does not reveal prefix correctness beyond what constant-time
  comparison permits

#### Scenario: No token leakage in logs or errors

- **WHEN** authentication fails
- **THEN** neither application logs nor the response body nor the re-rendered token page
  contain the expected token or the submitted token

#### Scenario: The submitted token is not echoed back into the form

- **WHEN** the token page is rendered, whether first visited or after a rejection
- **THEN** the token field is empty

### Requirement: Offline token generator utility

The system SHALL provide a built-in Mix task (e.g. `mix logger_dashboard.gen.token`) that prints a single URL-safe token of at least 128 bits of entropy using only Elixir/OTP built-ins, suitable for injecting via `DASHBOARD_AUTH_TOKEN`.

#### Scenario: Operator generates token offline

- **WHEN** an operator runs the generator task
- **THEN** it prints one URL-safe token to stdout with no side effects and exits zero

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

### Requirement: An authenticated session is bound to the current token

An authenticated session SHALL record evidence of which token established it, and the
system SHALL re-verify that evidence against the current valid token on every request
and on every LiveView mount. A session whose evidence does not match the current valid
token SHALL be treated as unauthenticated.

Consequently, replacing the configured token SHALL end every session established under
the previous one, including when the replacement is an ephemeral token generated at
boot. A session SHALL NOT outlive the token that established it.

#### Scenario: A rotated token ends outstanding sessions

- **WHEN** the configured token is replaced and a browser holding a session established
  with the previous token makes a request
- **THEN** the request is treated as unauthenticated and the operator is sent to the
  token page

#### Scenario: An ephemeral token regenerating ends outstanding sessions

- **WHEN** the dashboard restarts with no configured token, generating a new one, and a
  browser holds a session from the previous token
- **THEN** that session no longer authenticates and the operator is sent to the token
  page

#### Scenario: An unchanged token leaves a session working

- **WHEN** a session was established with the current valid token and that token is
  unchanged
- **THEN** the session continues to authenticate without asking for the token again

### Requirement: Signing out ends the session

The system SHALL offer a way to end an authenticated session from the dashboard. Signing
out SHALL end the session so that subsequent requests are unauthenticated, and SHALL
send the operator to the token page.

Signing out SHALL NOT delete logs, alter the configured token, or arm or disarm any
background work.

#### Scenario: Signing out ends the session

- **WHEN** an authenticated operator signs out and then requests a gated page
- **THEN** the request is unauthenticated and they are sent to the token page

#### Scenario: Signing out changes nothing else

- **WHEN** an authenticated operator signs out
- **THEN** the configured token is unchanged and no log data is deleted and no scheduled
  work is armed or disarmed

# Dashboard Auth Specification

## Purpose

Single shared-token gate in front of the dashboard so the destructive log browser and prune actions are no longer openly accessible, while staying operable via env or boot-generated tokens.

## Requirements

### Requirement: Token gate on dashboard routes

The system SHALL require a valid token for every dashboard route (`/`, `/logs`, `/analysis`, `/prune`, and `/dev/*` when enabled). Requests without a valid token SHALL be rejected with `401` and a `WWW-Authenticate` challenge so browsers ask for the token.

#### Scenario: Unauthenticated browser is asked for token

- **WHEN** an unauthenticated user visits `/logs`
- **THEN** the system responds `401` with a `WWW-Authenticate` header and does not render log data

#### Scenario: Valid token grants access

- **WHEN** a request presents the current valid token
- **THEN** the system serves the requested dashboard page normally

#### Scenario: Invalid token is rejected without oracle

- **WHEN** a request presents a wrong token
- **THEN** the system responds `401` without indicating whether the path exists or distinguishing wrong-token from missing-token

#### Scenario: LiveView sessions are gated

- **WHEN** a LiveView at `/logs`, `/analysis`, or `/prune` mounts or handles events over the socket
- **THEN** the system enforces the same token gate (initial HTTP plug plus socket/`on_mount` check) so bypassing the initial page load does not grant socket access

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

The system SHALL compare presented tokens with `Plug.Crypto.secure_compare/2` (or equivalent constant-time compare) after normalizing encoding, SHALL NOT log token values, and SHALL NOT reflect the expected token in error bodies.

#### Scenario: Timing-safe compare

- **WHEN** an attacker probes with varying prefixes of the real token
- **THEN** rejection timing does not reveal prefix correctness beyond what constant-time comparison permits

#### Scenario: No token leakage in logs or errors

- **WHEN** authentication fails
- **THEN** neither application logs nor the `401` response body contain the expected token or the presented token

### Requirement: Offline token generator utility

The system SHALL provide a built-in Mix task (e.g. `mix logger_dashboard.gen.token`) that prints a single URL-safe token of at least 128 bits of entropy using only Elixir/OTP built-ins, suitable for injecting via `DASHBOARD_AUTH_TOKEN`.

#### Scenario: Operator generates token offline

- **WHEN** an operator runs the generator task
- **THEN** it prints one URL-safe token to stdout with no side effects and exits zero

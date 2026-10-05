# Spec Delta

## ADDED Requirements

### Requirement: Release accepts LiveView socket origins from loopback and configured host
The system SHALL accept Phoenix socket (`/live`, websocket and longpoll) connections whose `Origin` is `localhost`, `127.0.0.1` (any scheme or port), or the configured `PHX_HOST`, while keeping origin checking enabled in the release. Connections from any other origin SHALL still be rejected.

#### Scenario: Dashboard loads over localhost
- **WHEN** an operator opens the dashboard at `http://localhost:<port>` on the release stack
- **THEN** the LiveView connects without a `Could not check origin` error and the page becomes interactive instead of retrying longpoll mounts

#### Scenario: Dashboard loads over 127.0.0.1
- **WHEN** an operator opens the dashboard at `http://127.0.0.1:<port>` on the release stack
- **THEN** the LiveView connects without a `Could not check origin` error and the page becomes interactive instead of retrying longpoll mounts

#### Scenario: Dashboard loads over the configured public host
- **WHEN** an operator opens the dashboard at the configured `PHX_HOST` origin
- **THEN** the LiveView connects without a `Could not check origin` error

#### Scenario: Foreign origins stay rejected
- **WHEN** a socket connection arrives with an `Origin` that is neither a loopback host nor the configured `PHX_HOST`
- **THEN** the connection is rejected by the origin check

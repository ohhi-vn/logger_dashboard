# Compose Deployment Specification

## Purpose

Gives operators a single declarative Podman Compose stack — dashboard plus a single-node ClickHouse — that builds the release image, provisions credentials, applies the ClickHouse schema before serving, and persists logs, so a working deployment needs no hand-assembled container commands and no Postgres instance.

## Requirements
### Requirement: Single-command stack startup

The system SHALL provide a compose file at the repository root that brings up the dashboard and a single-node ClickHouse, and nothing else, with one command from a clean checkout. The dashboard service SHALL declare a `build` section with context `.` and dockerfile `Containerfile` so `podman compose up --build` builds the image without a prebuilt image present, and the dashboard SHALL serve HTTP on the published dashboard port without any additional manual command.

#### Scenario: Bring the stack up from a clean checkout

- **WHEN** an operator copies the example environment file, fills in the required secrets, and runs `podman compose up --build`
- **THEN** the dashboard image is built from the repository `Containerfile`, ClickHouse starts, the ClickHouse schema is applied, and the dashboard serves HTTP on the published port without any additional manual command

#### Scenario: No undeclared backing service required

- **WHEN** an operator inspects the running stack
- **THEN** the only services are the dashboard and ClickHouse, with no database, cache, or proxy that the operator must supply separately

#### Scenario: No Postgres service or dependency

- **WHEN** an operator inspects the compose file and the environment file it reads
- **THEN** neither names a Postgres service, `DATABASE_URL`, `POOL_SIZE`, or any Postgres credential, and the stack starts without a Postgres instance reachable

#### Scenario: Docker compatibility

- **WHEN** an operator runs `docker compose up --build` instead
- **THEN** the same services, ordering, and credentials are used

#### Scenario: Build without a prebuilt image

- **WHEN** an operator removes any local `logger-dashboard:latest` image and runs `podman compose up --build` from a clean checkout
- **THEN** the compose tooling builds the dashboard image from `Containerfile` instead of failing with image-not-found

### Requirement: ClickHouse storage persists across restarts

The system SHALL store ClickHouse data in a named volume that survives `podman compose down` and container recreation.

#### Scenario: Data survives a full stop and start

- **WHEN** an operator runs `podman compose down` and later `podman compose up`
- **THEN** previously stored log rows are still readable through the dashboard

#### Scenario: Logs are deleted only on explicit volume removal

- **WHEN** an operator runs `podman compose down --volumes`
- **THEN** the ClickHouse data directory is destroyed and the next `up` starts from an empty store

### Requirement: ClickHouse is reachable only where intended

The system SHALL publish the ClickHouse HTTP and native ports on the host's loopback interface only, keeping the store and its credentials off the network. The server SHALL be configured to listen on `8124` (HTTP) and `9001` (native) inside the container, and the published mappings SHALL be literally `127.0.0.1:8124:8124` and `127.0.0.1:9001:9001`. The dashboard SHALL address it as `clickhouse:8124`.

#### Scenario: Published ClickHouse ports are loopback-bound

- **WHEN** an operator inspects the published ports of the running ClickHouse container
- **THEN** host ports `8124` and `9001` are bound to `127.0.0.1` and are not reachable from another host

#### Scenario: Dashboard reaches ClickHouse over the compose network

- **WHEN** the dashboard reads `/logs`, `/analysis`, or `/prune`
- **THEN** it connects to the ClickHouse service by its compose service name on port `8124`, with no host IP or published port involved

#### Scenario: Host inspection reaches the server ports

- **WHEN** an operator runs `curl http://127.0.0.1:8124/ping` against the running stack
- **THEN** the server answers rather than refusing the connection

### Requirement: Credentials come from an operator-supplied environment file

The system SHALL read all secrets from a gitignored environment file, ship a committed example file documenting every variable and how to generate it, and SHALL refuse to start when a required variable is absent.

#### Scenario: Missing secret fails before anything starts

- **WHEN** an operator runs `podman compose up` without `SECRET_KEY_BASE`, `DASHBOARD_AUTH_TOKEN`, or `CLICKHOUSE_PASSWORD` set
- **THEN** the command fails naming the missing variable, and no container is started with a default or empty secret

#### Scenario: Secrets are not committed

- **WHEN** an operator inspects version control after following the setup instructions
- **THEN** the populated environment file is ignored and only the example file is tracked

#### Scenario: Example file is actionable

- **WHEN** an operator reads the example environment file
- **THEN** it lists every variable the stack reads, marks the required ones, and gives the command that generates each generated value

#### Scenario: The dashboard authenticates to the password-protected ClickHouse

- **WHEN** an operator brings the stack up with a non-empty `CLICKHOUSE_PASSWORD`
- **THEN** the dashboard's ClickHouse URL carries those credentials so the server accepts its queries, and the deployment does not depend on a `CLICKHOUSE_USER`/`CLICKHOUSE_PASSWORD` pair that the client never sends

#### Scenario: Log rows are readable from the protected store

- **WHEN** an operator authenticates to `/logs` on a stack whose ClickHouse requires the password
- **THEN** log rows are returned from the store rather than an authentication or missing-table error

### Requirement: ClickHouse schema is applied before the dashboard serves

The system SHALL apply the ClickHouse DDL for the `logs` table before the dashboard starts serving, and SHALL wait for ClickHouse to accept authenticated queries before attempting it.

#### Scenario: No request is served against a missing table

- **WHEN** the dashboard container starts against an empty ClickHouse
- **THEN** it applies the schema first and only then begins serving, so no request is answered by a missing-table error

#### Scenario: Startup waits for ClickHouse readiness

- **WHEN** the dashboard container starts while ClickHouse is still booting
- **THEN** the dashboard waits for ClickHouse to become ready instead of failing immediately

#### Scenario: Failed schema application keeps the service down

- **WHEN** the schema application fails, for example because the ClickHouse credentials are wrong
- **THEN** the dashboard container exits with a non-zero status and serves no traffic, leaving the failure visible to the operator

#### Scenario: Re-running against an existing store is harmless

- **WHEN** the dashboard container restarts against a ClickHouse that already holds the `logs` table
- **THEN** the schema application completes without error and the dashboard serves normally

### Requirement: Operator lifecycle is documented

The system SHALL document, in the project README, the prerequisites, secret generation, and the commands to start, inspect, stop, and reset the stack.

#### Scenario: Documented steps reproduce a working deployment

- **WHEN** an operator follows only the README deployment section on a machine with Podman and Podman Compose
- **THEN** they end up with a running dashboard they can authenticate to using the generated token

#### Scenario: Logs are reachable for troubleshooting

- **WHEN** an operator follows the README to view container output
- **THEN** the documented command shows the dashboard boot output, including the shared token when one was generated instead of set

### Requirement: Stack health is reported by the compose tooling

The system SHALL declare health checks for both services in the compose file so the tooling reports their state without depending on image metadata.

#### Scenario: Health is reported regardless of image build format

- **WHEN** the dashboard image is built by the compose tooling without the Docker image format
- **THEN** the dashboard still reports a health status derived from an HTTP response of the running release

#### Scenario: ClickHouse health reflects authenticated readiness

- **WHEN** ClickHouse is running but rejects the dashboard's credentials
- **THEN** the ClickHouse service is reported as unhealthy and the dashboard does not begin its schema application

### Requirement: Plain-HTTP access is limited to loopback

The system SHALL document that the stack serves plain HTTP, and that the release's force-SSL redirect exempts only `localhost` and `127.0.0.1`.

#### Scenario: Browser access on the loopback host

- **WHEN** an operator opens the dashboard at `http://localhost:<port>` from the host running the stack
- **THEN** the page loads and prompts for the shared token instead of redirecting to HTTPS

#### Scenario: Non-loopback access requires TLS termination

- **WHEN** an operator opens the dashboard by any other host name or address over plain HTTP
- **THEN** the release responds with a redirect to HTTPS, and the README states that TLS must be terminated in front of the published port

### Requirement: Dashboard operational configuration persists across recreation

The system SHALL store the dashboard's operational configuration in a named volume
that survives `podman compose down` and container recreation, so configuration an
operator saved through the dashboard is still in force after a redeploy.

Removing the volumes SHALL remove that configuration, returning the dashboard to its
configured defaults.

#### Scenario: Saved configuration survives a redeploy

- **WHEN** an operator saves dashboard configuration, runs `podman compose down`, and
  later runs `podman compose up`
- **THEN** the saved configuration is still in force

#### Scenario: Configuration is deleted only on explicit volume removal

- **WHEN** an operator runs `podman compose down --volumes`
- **THEN** the saved dashboard configuration is destroyed and the dashboard returns to
  its configured defaults

#### Scenario: The stack still declares no additional service

- **WHEN** an operator inspects the running stack after this change
- **THEN** the only services are the dashboard and ClickHouse; the configuration store
  is a volume on the dashboard service, not a new service

#### Scenario: The example environment file documents the store location

- **WHEN** an operator reads the example environment file
- **THEN** it lists the variable naming the dashboard's configuration directory and
  states that the directory is backed by a named volume

### Requirement: Dashboard published port matches the release listen port

The system SHALL pass `DASHBOARD_PORT` (default `5051`) into the dashboard container so the release listens on it, and SHALL publish literally `127.0.0.1:${DASHBOARD_PORT:-5051}:${DASHBOARD_PORT:-5051}` (default `5051:5051`), so the documented `http://localhost:5051` works without overriding anything.

#### Scenario: Default stack serves on documented port

- **WHEN** an operator brings the stack up with no `DASHBOARD_PORT` set
- **THEN** the dashboard is reachable at `http://localhost:5051` and prompts for the shared token instead of refusing the connection

#### Scenario: In-container probe matches the listen port

- **WHEN** the dashboard container is running
- **THEN** its compose healthcheck probes `http://localhost:5051/logs` (or the configured `DASHBOARD_PORT`) inside the container, the same port the release listens on

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

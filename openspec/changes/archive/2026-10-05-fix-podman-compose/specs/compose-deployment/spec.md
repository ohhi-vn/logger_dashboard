# Spec Delta

## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: Dashboard published port matches the release listen port
The system SHALL pass `DASHBOARD_PORT` (default `5051`) into the dashboard container so the release listens on it, and SHALL publish literally `127.0.0.1:${DASHBOARD_PORT:-5051}:${DASHBOARD_PORT:-5051}` (default `5051:5051`), so the documented `http://localhost:5051` works without overriding anything.

#### Scenario: Default stack serves on documented port
- **WHEN** an operator brings the stack up with no `DASHBOARD_PORT` set
- **THEN** the dashboard is reachable at `http://localhost:5051` and prompts for the shared token instead of refusing the connection

#### Scenario: In-container probe matches the listen port
- **WHEN** the dashboard container is running
- **THEN** its compose healthcheck probes `http://localhost:5051/logs` (or the configured `DASHBOARD_PORT`) inside the container, the same port the release listens on

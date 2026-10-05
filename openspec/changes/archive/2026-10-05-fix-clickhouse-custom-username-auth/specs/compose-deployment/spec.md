# Spec Delta

## MODIFIED Requirements

### Requirement: Credentials come from an operator-supplied environment file

The system SHALL read all secrets from a gitignored environment file, ship a committed example file documenting every variable and how to generate it, and SHALL refuse to start when a required variable is absent. The system SHALL honor the configured `CLICKHOUSE_USER` (default `default`) together with `CLICKHOUSE_PASSWORD` when building the dashboard's effective ClickHouse URL, so the credentials on the wire always match the provisioned ClickHouse user.

#### Scenario: Missing secret fails before anything starts

- **WHEN** an operator runs `podman compose up` without `SECRET_KEY_BASE`, `DASHBOARD_AUTH_TOKEN`, or `CLICKHOUSE_PASSWORD` set
- **THEN** the command fails naming the missing variable, and no container is started with a default or empty secret

#### Scenario: Secrets are not committed

- **WHEN** an operator inspects version control after following the setup instructions
- **THEN** the populated environment file is ignored and only the example file is tracked

#### Scenario: Example file is actionable

- **WHEN** an operator reads the example environment file
- **THEN** it lists every variable the stack reads including `CLICKHOUSE_USER` with its `default` default, marks the required ones, and gives the command that generates each generated value

#### Scenario: The dashboard authenticates to the password-protected ClickHouse

- **WHEN** an operator brings the stack up with a non-empty `CLICKHOUSE_PASSWORD`
- **THEN** the dashboard's effective ClickHouse URL carries the configured `CLICKHOUSE_USER` and password so the server accepts its queries

#### Scenario: Log rows are readable from the protected store

- **WHEN** an operator authenticates to `/logs` on a stack whose ClickHouse requires the password
- **THEN** log rows are returned from the store rather than an authentication or missing-table error

### Requirement: Stack health is reported by the compose tooling

The system SHALL declare health checks for both services in the compose file so the tooling reports their state without depending on image metadata.

#### Scenario: Health is reported regardless of image build format

- **WHEN** the dashboard image is built by the compose tooling without the Docker image format
- **THEN** the dashboard still reports a health status derived from an HTTP response of the running release

#### Scenario: ClickHouse health reflects authenticated readiness

- **WHEN** ClickHouse is running but rejects the dashboard's credentials
- **THEN** the ClickHouse service is reported as unhealthy and the dashboard does not begin its schema application

#### Scenario: ClickHouse health uses the configured user

- **WHEN** the stack sets a custom `CLICKHOUSE_USER`
- **THEN** the ClickHouse healthcheck authenticates as that user rather than hardcoded `default`, so a correctly provisioned custom user reports healthy

## ADDED Requirements

### Requirement: Custom ClickHouse username connects

The system SHALL connect to ClickHouse as the configured `CLICKHOUSE_USER` for every dashboard query, migration, and health probe. When `CLICKHOUSE_URL` already carries userinfo, the system SHALL preserve it and SHALL NOT inject a second userinfo. When it carries none, the system SHALL inject the percent-encoded `CLICKHOUSE_USER` and `CLICKHOUSE_PASSWORD`.

#### Scenario: Custom user reaches logs and analysis

- **WHEN** an operator sets `CLICKHOUSE_USER` to a provisioned non-`default` user with the matching `CLICKHOUSE_PASSWORD` and brings the stack up
- **THEN** schema bootstrap succeeds and `/logs`, `/analysis`, and `/prune` return rows instead of code 194 `REQUIRED_PASSWORD` for `default`

#### Scenario: Explicit userinfo URL wins

- **WHEN** an operator sets `CLICKHOUSE_URL` with userinfo already present alongside `CLICKHOUSE_USER`/`CLICKHOUSE_PASSWORD`
- **THEN** the dashboard connects with the URL's userinfo unchanged

#### Scenario: Special characters in credentials stay well-formed

- **WHEN** the configured username or password contains characters reserved in URL userinfo
- **THEN** the effective URL percent-encodes them so authentication still succeeds and the URL parses

#### Scenario: Default behavior is unchanged

- **WHEN** an operator leaves `CLICKHOUSE_USER` unset
- **THEN** the dashboard connects as `default`, preserving the current single-user deployment

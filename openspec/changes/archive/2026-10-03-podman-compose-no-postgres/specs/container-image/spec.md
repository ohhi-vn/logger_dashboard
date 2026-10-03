# Spec Delta

## MODIFIED Requirements

### Requirement: Runtime configuration via environment

The system SHALL configure the release exclusively via environment variables at runtime with no code change: `PHX_HOST`, `PORT`, `SECRET_KEY_BASE`, `CLICKHOUSE_URL`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`, `CLICKHOUSE_DATABASE`, and `DASHBOARD_AUTH_TOKEN`. The release SHALL boot and serve without any Postgres database: no `DATABASE_URL`, `POOL_SIZE`, or `ECTO_IPV6` variable is read, and no Postgres repo is configured or started.

#### Scenario: Missing release secrets fail fast

- **WHEN** the container starts in prod without `SECRET_KEY_BASE`
- **THEN** it raises at boot with a message naming the missing variable instead of serving traffic with defaults

#### Scenario: Boot without a Postgres database

- **WHEN** the container starts in prod with no Postgres environment set and a reachable ClickHouse
- **THEN** it boots and serves traffic, having started no Postgres repo, and its routes read only from ClickHouse

#### Scenario: Postgres environment is not consulted

- **WHEN** the container starts in prod with `DATABASE_URL` set to some value
- **THEN** the value is ignored: no connection is attempted and no failures reference Postgres

#### Scenario: ClickHouse connectivity via env

- **WHEN** `CLICKHOUSE_URL`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`, and `CLICKHOUSE_DATABASE` are set
- **THEN** `/logs` reads from that ClickHouse instance with no rebuild

#### Scenario: Credentials for a protected server travel in the URL

- **WHEN** `CLICKHOUSE_URL` addresses a ClickHouse that requires authentication
- **THEN** the credentials are taken from the URL's userinfo, and setting `CLICKHOUSE_USER`/`CLICKHOUSE_PASSWORD` alone does not authenticate the client

# Spec Delta

## MODIFIED Requirements

### Requirement: Runtime configuration via environment

The system SHALL configure the release exclusively via environment variables at runtime with no code change: `PHX_HOST`, `PORT`, `SECRET_KEY_BASE`, `POOL_SIZE`, `DATABASE_URL`, `CLICKHOUSE_URL`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`, `CLICKHOUSE_DATABASE`, and `DASHBOARD_AUTH_TOKEN`. `DATABASE_URL` SHALL be optional: when it is absent the release SHALL boot without configuring or starting the Postgres repo, and when it is present the repo SHALL be configured and supervised as before.

#### Scenario: Missing release secrets fail fast

- **WHEN** the container starts in prod without `SECRET_KEY_BASE`
- **THEN** it raises at boot with a message naming the missing variable instead of serving traffic with defaults

#### Scenario: Boot without a Postgres database

- **WHEN** the container starts in prod with `DATABASE_URL` unset and a reachable ClickHouse
- **THEN** it boots and serves traffic, having started no Postgres repo, and its routes read only from ClickHouse

#### Scenario: Explicit Postgres configuration is still honored

- **WHEN** the container starts in prod with `DATABASE_URL` set
- **THEN** the Postgres repo is configured from that URL, `POOL_SIZE`, and `ECTO_IPV6` exactly as before

#### Scenario: ClickHouse connectivity via env

- **WHEN** `CLICKHOUSE_URL`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`, and `CLICKHOUSE_DATABASE` are set
- **THEN** `/logs` reads from that ClickHouse instance with no rebuild
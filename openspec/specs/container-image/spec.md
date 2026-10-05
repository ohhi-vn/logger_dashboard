# Container Image Specification

## Purpose

Reproducible OCI image build for the Phoenix release so operators can run the dashboard with podman or docker without hand-rolling Dockerfiles.

## Requirements
### Requirement: Multi-stage container build

The system SHALL provide a `Containerfile` at the repository root that builds a runnable release image with `podman build` and `docker build` without modification.

#### Scenario: Build image with podman

- **WHEN** an operator runs `podman build -t logger-dashboard -f Containerfile .`
- **THEN** the build completes and produces a runnable image without requiring local Elixir/OTP installed

#### Scenario: Build image with docker

- **WHEN** an operator runs `docker build -t logger-dashboard -f Containerfile .`
- **THEN** the build completes with the same stages and entrypoint as the podman build

#### Scenario: Build compiles assets and release

- **WHEN** the builder stage runs
- **THEN** it installs Hex/Rebar deps, compiles with `MIX_ENV=prod`, runs `mix assets.deploy`, runs `mix release`, and copies only the release artifact into the runner stage

### Requirement: Non-root minimal runtime

The system SHALL run the release as a non-root user, listen on `$DASHBOARD_PORT` (default `4000`), and start with `PHX_SERVER=true` semantics so the endpoint serves traffic.

The image SHALL provide a writable directory owned by the runtime user for the
dashboard's operational configuration store, defaulting to a path inside the release
directory, so the release can persist configuration without running as root and
without the operator having to pre-create anything.

#### Scenario: Run as non-root

- **WHEN** the image starts
- **THEN** the app process runs as a non-root UID and the release directory and writable paths are owned/accessible by that user

#### Scenario: Serve traffic on configured port

- **WHEN** the container starts with default env plus required secrets
- **THEN** the endpoint accepts HTTP on `$PORT` and serves `/` (behind the auth gate, see `dashboard-auth`) without crash-looping

#### Scenario: The configuration store directory is writable by the runtime user

- **WHEN** the image starts with no configuration store directory specified
- **THEN** the release can create and write its default configuration store directory as the non-root user, without the operator pre-creating it

### Requirement: Runtime configuration via environment

The system SHALL configure the release exclusively via environment variables at runtime with no code change: `PHX_HOST`, `PORT`, `SECRET_KEY_BASE`, `CLICKHOUSE_URL`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`, `CLICKHOUSE_DATABASE`, `DASHBOARD_AUTH_TOKEN`, and the variable naming the dashboard's configuration store directory. The release SHALL boot and serve without any Postgres database: no `DATABASE_URL`, `POOL_SIZE`, or `ECTO_IPV6` variable is read, and no Postgres repo is configured or started.

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

#### Scenario: Configuration store directory via env

- **WHEN** the container starts with the configuration store directory variable set to
  a mounted path
- **THEN** saved dashboard configuration is written to and read from that path with no
  rebuild

#### Scenario: An unwritable configuration store directory does not stop the release

- **WHEN** the container starts with the configuration store directory variable set to a
  path that cannot be created or written
- **THEN** the release still boots and serves traffic, and background tasks fall back to
  their configured defaults

### Requirement: Container build hygiene

The system SHALL provide a `.containerignore` (or extend `.dockerignore`) excluding `_build/`, `deps/`, `cover/`, `doc/`, `tmp/`, git metadata, and local digested-asset output so builds are reproducible and contexts stay small.

#### Scenario: Small build context

- **WHEN** an operator builds the image from a working checkout with prior local `_build/` and `deps/`
- **THEN** those directories are excluded from the build context and do not invalidate builder caching or bloat the image

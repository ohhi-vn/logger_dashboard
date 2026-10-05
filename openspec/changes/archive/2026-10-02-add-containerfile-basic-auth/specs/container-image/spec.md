# Spec Delta

## Purpose

Reproducible OCI image build for the Phoenix release so operators can run the dashboard with podman or docker without hand-rolling Dockerfiles.

## ADDED Requirements

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

#### Scenario: Run as non-root

- **WHEN** the image starts
- **THEN** the app process runs as a non-root UID and the release directory and writable paths are owned/accessible by that user

#### Scenario: Serve traffic on configured port

- **WHEN** the container starts with default env plus required secrets
- **THEN** the endpoint accepts HTTP on `$PORT` and serves `/` (behind the auth gate, see `dashboard-auth`) without crash-looping

### Requirement: Runtime configuration via environment

The system SHALL configure the release exclusively via environment variables at runtime with no code change: `PHX_HOST`, `PORT`, `SECRET_KEY_BASE`, `DATABASE_URL`, `POOL_SIZE`, `CLICKHOUSE_URL`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`, `CLICKHOUSE_DATABASE`, and `DASHBOARD_AUTH_TOKEN`.

#### Scenario: Missing release secrets fail fast

- **WHEN** the container starts in prod without `SECRET_KEY_BASE` or `DATABASE_URL`
- **THEN** it raises at boot with a message naming the missing variable instead of serving traffic with defaults

#### Scenario: ClickHouse connectivity via env

- **WHEN** `CLICKHOUSE_URL`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`, and `CLICKHOUSE_DATABASE` are set
- **THEN** `/logs` reads from that ClickHouse instance with no rebuild

### Requirement: Container build hygiene

The system SHALL provide a `.containerignore` (or extend `.dockerignore`) excluding `_build/`, `deps/`, `cover/`, `doc/`, `tmp/`, git metadata, and local digested-asset output so builds are reproducible and contexts stay small.

#### Scenario: Small build context

- **WHEN** an operator builds the image from a working checkout with prior local `_build/` and `deps/`
- **THEN** those directories are excluded from the build context and do not invalidate builder caching or bloat the image

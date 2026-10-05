# Spec Delta

## MODIFIED Requirements

### Requirement: ClickHouse storage persists across restarts

The system SHALL store ClickHouse data in a named volume that survives `podman compose down` and container recreation.

#### Scenario: Data survives a full stop and start

- **WHEN** an operator runs `podman compose down` and later `podman compose up`
- **THEN** previously stored log rows are still readable through the dashboard

#### Scenario: Logs are deleted only on explicit volume removal

- **WHEN** an operator runs `podman compose down --volumes`
- **THEN** the ClickHouse data directory is destroyed and the next `up` starts from an empty store

## ADDED Requirements

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
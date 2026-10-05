# Spec Delta

## Purpose

Gives the dashboard's background tasks a durable place to keep operator-supplied
configuration, so a task's settings survive a restart and a container recreation
rather than reverting to whatever the environment happens to declare.

## ADDED Requirements

### Requirement: Background task configuration is keyed by task

The system SHALL store each background task's configuration under that task's own
key, so one task's configuration cannot be read, written, or cleared as another
task's. A task with no stored configuration SHALL read as having none, rather than
reading another task's value or an error.

Storing a value for one task SHALL NOT alter the stored configuration of any other
task.

#### Scenario: A task reads its own stored value

- **WHEN** a value has been stored for one task and a different task reads its
  configuration
- **THEN** the second task reads no stored value of its own

#### Scenario: Clearing one task leaves the others alone

- **WHEN** the configuration for one task is cleared
- **THEN** configuration stored for other tasks is unchanged

### Requirement: Stored configuration is durable

A configuration value that has been stored SHALL still be present after the dashboard
application restarts. Durability SHALL come from a directory the operator can place on
persistent storage, and the system SHALL NOT require a database server, a schema
migration, or a table it does not own in order to keep it.

#### Scenario: A stored value survives an application restart

- **WHEN** a task's configuration is stored and the dashboard application is restarted
- **THEN** the task reads the same value it stored before the restart

#### Scenario: The store's location is configurable

- **WHEN** the operator changes the directory the configuration store uses
- **THEN** the store uses the new directory, and nothing is written under the previous
  one

#### Scenario: No owned database schema is required

- **WHEN** the dashboard is deployed with a configuration store directory
- **THEN** no additional database, table, or migration is required for the stored
  configuration to persist

### Requirement: A stored value is validated before use

A stored value SHALL be validated by the owning task before it is used, and a stored
value the task cannot use SHALL be treated exactly as though nothing were stored —
the task SHALL fall back to its configured default rather than acting on a value it
could not interpret. A value that fails validation SHALL NOT be silently rewritten to
the default, so the operator can see that their stored configuration is not in effect
and why.

Reading a stored value SHALL NOT modify it.

#### Scenario: An unusable stored value falls back to the configured default

- **WHEN** the store holds a value the task cannot interpret
- **THEN** the task behaves as though nothing were stored and uses its configured
  default

#### Scenario: An unusable stored value is reported rather than overwritten

- **WHEN** the store holds a value the task cannot interpret
- **THEN** the problem is surfaced to the operator and the stored value is left in
  place

#### Scenario: Reading does not modify the stored value

- **WHEN** a stored value is read
- **THEN** the stored value is unchanged by that read

### Requirement: The store is scoped to one dashboard instance

The store SHALL be local to the dashboard instance that writes it. Where more than one
dashboard instance runs, each SHALL keep its own configuration and SHALL NOT assume
that a write made on one instance is visible on another.

#### Scenario: A write on one instance is not visible on another

- **WHEN** configuration is stored on one dashboard instance and another dashboard
  instance reads that task's configuration
- **THEN** the second instance does not see the write and uses its own configuration

### Requirement: Store unavailability does not stop the dashboard

When the configuration store cannot be opened or read — a missing directory, an
unwritable path, or a corrupt store file — the dashboard SHALL still start and serve
requests, and each background task SHALL fall back to its configured default. A
failed read SHALL be reported rather than presented as an empty store.

#### Scenario: An unopenable store still yields a running dashboard

- **WHEN** the store directory does not exist and cannot be created
- **THEN** the dashboard starts normally, and background tasks use their configured
  defaults

#### Scenario: A store failure is reported

- **WHEN** the store cannot be opened or read
- **THEN** the failure is surfaced rather than the store appearing empty
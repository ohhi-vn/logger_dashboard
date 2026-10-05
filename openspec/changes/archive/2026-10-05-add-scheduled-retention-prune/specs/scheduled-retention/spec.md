# Spec Delta

## Purpose

Lets an operator define a log-retention policy that the dashboard applies on a
schedule, so ClickHouse log storage is bounded by policy rather than by an operator
remembering to prune it.

## ADDED Requirements

### Requirement: Retention policy

The system SHALL hold a retention policy comprising an enabled flag, a time of day
at which the policy runs, and a retained age expressed in hours or days. The
retained age SHALL be applied as a cutoff relative to the instant of each run: at a
run, rows whose `timestamp` is older than the retained age as of that run instant
SHALL be in scope for deletion, and no row newer than that cutoff SHALL be. The
retained age SHALL be chosen from the same relative-cutoff vocabulary the prune page
already offers for age cutoffs, so that the scheduled policy and a manual age cutoff
name the same set of durations.

The policy SHALL cover the whole system rather than a single node, and SHALL NOT be
configurable to a single-node scope.

#### Scenario: Policy holds a run time, a retained age, and an enabled flag

- **WHEN** the effective retention policy is inspected
- **THEN** it reports an enabled flag, a time of day to run, and a retained age

#### Scenario: Retained age is a cutoff relative to the run instant

- **WHEN** a run occurs with a retained age of 7 days
- **THEN** rows older than 7 days as of that run instant are in scope and rows newer
  than that cutoff are not

#### Scenario: Retained age is expressed in hours or days

- **WHEN** the retained age is chosen
- **THEN** it can be expressed in hours as well as in days

#### Scenario: Policy applies to the whole system

- **WHEN** a scheduled run is dispatched
- **THEN** its scope is every node rather than one selected node

### Requirement: Configured policy default

The system SHALL read a retention policy default from application configuration and
the environment. That configured default SHALL survive a restart of the dashboard,
and it SHALL be the effective policy whenever no runtime override is present.

An absent or empty configured value SHALL leave the feature off rather than failing
the boot, so a deployment that configures no retention policy starts normally with
scheduled pruning disabled.

#### Scenario: Configured default is the effective policy with no override

- **WHEN** no runtime override is present
- **THEN** the effective retention policy is the configured default

#### Scenario: Configured default survives a restart

- **WHEN** the dashboard restarts
- **THEN** the effective retention policy is the configured default again

#### Scenario: Unconfigured policy leaves the feature off

- **WHEN** no retention policy is configured
- **THEN** the dashboard starts normally and scheduled pruning is disabled

### Requirement: Runtime policy override

The system SHALL allow the retention policy to be edited from the prune page for the
running system. That edit SHALL be an override held in memory only, and it SHALL NOT
be written to the configured default, because the dashboard SHALL NOT write its own
configuration.

When the override is present it SHALL be the effective policy. When the runtime
override is absent — including after a restart — the system SHALL fall back to the
configured default. The prune page SHALL show the effective policy and SHALL
distinguish which of the two supplied it, so an operator can tell whether the policy
in force is the configured one or an override that will not survive a restart.

#### Scenario: Editing the policy changes the effective policy

- **WHEN** the policy is edited on the prune page
- **THEN** the effective policy reflects the edit

#### Scenario: An override does not survive a restart

- **WHEN** the policy was edited from the prune page and the dashboard then restarts
- **THEN** the effective policy is the configured default rather than the edit

#### Scenario: The page shows which layer supplied the policy

- **WHEN** the prune page displays the retention policy
- **THEN** it shows the effective policy and identifies whether it came from the
  configured default or from a runtime override that will not survive a restart

### Requirement: Explicit confirmation before arming unattended deletes

The system SHALL require an explicit confirmation step before a scheduled retention
policy is armed, and SHALL perform no unattended delete until that confirmation is
given. The confirmation SHALL state the resolved scope and retained age being armed.

Cancelling at the confirmation step SHALL leave the policy unarmed and SHALL delete
no rows. A policy that is already armed SHALL NOT require confirmation again to keep
running.

#### Scenario: Arming requires confirmation

- **WHEN** an operator submits a request to enable scheduled retention
- **THEN** the system asks for explicit confirmation stating the resolved scope and
  retained age, and deletes nothing until that confirmation is given

#### Scenario: Cancelling leaves the policy unarmed

- **WHEN** the operator cancels at the confirmation step
- **THEN** no unattended delete is armed and no rows are deleted

#### Scenario: An already-armed policy keeps running without re-confirmation

- **WHEN** a confirmed retention policy runs again at its next scheduled time
- **THEN** it runs without asking for confirmation again

### Requirement: Unattended runs are logged

Each unattended retention run SHALL record the scope it acted on, the cutoff it
applied, and whether the delete was dispatched or failed, so that recurring deletes
leave an audit trail without an operator present.

A failed unattended run SHALL record the failure reason rather than failing silently,
and SHALL NOT be treated as a successful delete.

#### Scenario: A successful unattended run records its scope

- **WHEN** a scheduled run dispatches its delete
- **THEN** the scope acted on and the applied cutoff are recorded

#### Scenario: A failed unattended run records the reason

- **WHEN** a scheduled run's delete fails
- **THEN** the failure and its reason are recorded rather than the run being reported
  as successful

### Requirement: No catch-up run on restart

The system SHALL apply the policy only at its scheduled times. A dashboard that was
not running when a scheduled time passed SHALL NOT run the policy on boot to catch
up, and SHALL wait for the next scheduled occurrence instead.

This SHALL hold across restarts, so that a process repeatedly restarting cannot cause
repeated unattended deletes.

#### Scenario: A missed occurrence is not run on boot

- **WHEN** the dashboard starts after a scheduled time passed while it was not
  running
- **THEN** it performs no delete on boot and waits for the next scheduled occurrence

#### Scenario: Repeated restarts do not cause repeated deletes

- **WHEN** the dashboard restarts several times in succession
- **THEN** no unattended delete is performed on any of those boots
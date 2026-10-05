# Scheduled Retention Specification

## Purpose

Lets an operator define a log-retention policy that the dashboard applies on a
schedule, so ClickHouse log storage is bounded by policy rather than by an operator
remembering to prune it.

## Requirements

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
the environment. That configured default SHALL be the effective policy whenever no
stored policy is present, and a stored policy SHALL take precedence over it.

An absent or empty configured value SHALL leave the feature off rather than failing
the boot, so a deployment that configures no retention policy starts normally with
scheduled pruning disabled.

A stored policy SHALL NOT be removed because the configured default changed; the
configured value governs only until something is stored, and reverting to the
configured default is an explicit operator action.

#### Scenario: Configured default is the effective policy with no override

- **WHEN** no stored retention policy is present
- **THEN** the effective retention policy is the configured default

#### Scenario: Configured default survives a restart

- **WHEN** the dashboard restarts
- **THEN** the effective retention policy is the configured default again

#### Scenario: Unconfigured policy leaves the feature off

- **WHEN** no retention policy is configured
- **THEN** the dashboard starts normally and scheduled pruning is disabled

#### Scenario: A changed configured default does not discard a stored policy

- **WHEN** a retention policy is stored and the configured default is then changed
- **THEN** the stored policy remains in force

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

### Requirement: Stored policy override

The system SHALL allow the retention policy to be edited from the prune page for the
running system. That edit SHALL be stored in the durable background-task
configuration store, and SHALL NOT be written to the application-environment
configured default; the dashboard writes its own operational configuration and never
rewrites the environment it was deployed with.

When a stored policy is present it SHALL be the effective policy, including after a
restart. When none is present, the system SHALL fall back to the configured default.
The prune page SHALL show the effective policy and SHALL distinguish which of the two
supplied it, and SHALL state that a stored policy survives a restart.

The page SHALL offer a way to return to the configured default, and taking it SHALL
remove the stored policy so the configured default is in force again — for this
running system and for the next one.

#### Scenario: An edited policy survives a restart

- **WHEN** an operator saves a policy from the prune page and then confirms it, and
  the dashboard later restarts
- **THEN** the effective policy is that saved policy rather than the configured
  default

#### Scenario: The page shows which layer supplied the policy

- **WHEN** the prune page displays the retention policy
- **THEN** it shows the effective policy and identifies whether it came from the
  configured default or from a stored value, and states that a stored value survives
  a restart

#### Scenario: Reverting removes the stored policy

- **WHEN** the operator reverts to the configured default on the prune page
- **THEN** the stored policy is removed and the configured default is in force, again
  and after a restart

### Requirement: An enabled policy is neither written nor armed before it is confirmed

Saving a retention policy from the prune page SHALL NOT write it and SHALL NOT arm a
schedule for it until an operator confirms it. The confirmation SHALL state the
resolved scope and retained age being saved, and SHALL make clear that nothing has
been written yet.

Before that confirmation the policy SHALL exist nowhere: not in the configuration
store, not as the effective policy, and not as a pending scheduled run. Cancelling at
the confirmation step SHALL leave the previously effective policy in force, write
nothing, and delete no rows.

A policy that is disabled SHALL be written without a confirmation step, because it
deletes nothing and arms nothing.

#### Scenario: Saving an enabled policy writes nothing until it is confirmed

- **WHEN** an operator submits an enabled retention policy on the prune page and has
  not confirmed it
- **THEN** the policy is not in the configuration store, the previously effective
  policy remains in force, and no scheduled run is pending for it

#### Scenario: The confirmation states the resolved scope and that nothing is saved yet

- **WHEN** an operator submits an enabled retention policy
- **THEN** the system asks for confirmation stating the resolved scope and retained
  age, and says that nothing has been saved

#### Scenario: Confirming saves the policy and arms it

- **WHEN** the operator confirms the pending policy
- **THEN** the policy is written to the configuration store and becomes the effective
  scheduled policy

#### Scenario: Cancelling leaves the previous policy in force

- **WHEN** the operator cancels at the confirmation step
- **THEN** no policy is written, the policy in force is unchanged, and no rows are
  deleted

#### Scenario: An armed policy can be stopped without a confirmation step

- **WHEN** an armed policy is turned off from the prune page, or its saved policy is
  removed
- **THEN** the schedule is disarmed and no pending run remains, without a confirmation
  step

### Requirement: A stored policy that cannot be used does not silently prune

If the stored retention policy cannot be interpreted — for example because its
retained age is no longer a member of the age vocabulary — the system SHALL treat it
as absent for the purpose of running the schedule, so it falls back to the configured
default rather than pruning against an uninterpretable cutoff. The condition SHALL be
reported to the operator, and the stored value SHALL be left in place so it can be
inspected or replaced.

#### Scenario: An uninterpretable stored policy does not schedule a delete

- **WHEN** the store holds a retention policy whose retained age is not a member of
  the age vocabulary
- **THEN** no delete is scheduled from it and the configured default governs the
  schedule

#### Scenario: An uninterpretable stored policy is surfaced

- **WHEN** the store holds a retention policy that cannot be interpreted
- **THEN** the prune page reports that the stored policy is not in effect and why, and
  the stored value is left in place

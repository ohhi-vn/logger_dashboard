# Spec Delta

## MODIFIED Requirements

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

## REMOVED Requirements

### Requirement: Runtime policy override

**Reason**: The requirement defined the edit as an in-memory-only override that is
discarded on restart, and its scenarios assert that loss. The dashboard now has a
durable store on persistent storage, so the same edit is persisted and the "does not
survive a restart" behaviour is no longer the system's intent — an operator who armed
a system-wide delete should not find it silently reverted by a deploy.

**Migration**: The edit is now the stored policy, named by the added requirements
below. It replaces the configured default while present, survives a restart, and is
removed by the page's revert action, which returns the system to the configured
default for this run and every later one. A deployment that relied on an edit
reverting on restart will now find the edit still in force until reverted; use the
page's revert action to restore the previous behaviour. An older release reading the
same store ignores it and falls back to the configured default, so rollback needs no
data migration.

## ADDED Requirements

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
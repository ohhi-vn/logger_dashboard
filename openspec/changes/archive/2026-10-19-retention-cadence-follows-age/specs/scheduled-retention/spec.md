# Spec Delta

## MODIFIED Requirements

### Requirement: Retention policy

The system SHALL hold a retention policy comprising an enabled flag, a time of day
at which the policy runs, and a retained age expressed in hours or days. The
retained age SHALL be applied as a cutoff relative to the instant of each run: at a
run, rows whose `timestamp` is older than the retained age as of that run instant
SHALL be in scope for deletion, and no row newer than that cutoff SHALL be. The
retained age SHALL be chosen from the same relative-cutoff vocabulary the prune page
already offers for age cutoffs, so that the scheduled policy and a manual age cutoff
name the same set of durations.

The cadence at which the policy runs SHALL follow the retained age: a retained age
expressed in hours SHALL schedule one run every hour on the hour, and a retained age
expressed in days SHALL schedule one run per day at the policy's time of day. The
time of day SHALL govern only a day-valued retained age; an hour-valued retained age
SHALL run on the hour regardless of it. The cadence SHALL be derived from the
retained age rather than chosen or stored separately, so the schedule cannot
disagree with the age it enforces.

The policy SHALL cover the whole system rather than a single node, and SHALL NOT be
configurable to a single-node scope.

#### Scenario: Policy holds a run time, a retained age, and an enabled flag

- **WHEN** the effective retention policy is inspected
- **THEN** it reports an enabled flag, a time of day, and a retained age

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

#### Scenario: An hour-valued retained age runs every hour

- **WHEN** the effective policy's retained age is expressed in hours (1 hour, 6
  hours, or 12 hours)
- **THEN** the schedule fires at the top of every hour, regardless of the policy's
  time of day

#### Scenario: A day-valued retained age keeps the daily run at the policy's time

- **WHEN** the effective policy's retained age is expressed in days (1, 3, 7, 30, or
  90 days)
- **THEN** the schedule fires once per day at the policy's time of day, as it did
  before this cadence rule existed

#### Scenario: The run-at time does not affect an hour-valued age

- **WHEN** an operator arms a policy whose retained age is expressed in hours with
  some run-at time of day submitted alongside it
- **THEN** the armed schedule runs on the hour regardless of that run-at value

#### Scenario: Changing the retained age's unit changes the cadence

- **WHEN** the effective policy's retained age changes from a day-valued age to an
  hour-valued age, or from an hour-valued age back to a day-valued age
- **THEN** the cadence follows the new age without any separate schedule setting
  being stored or changed

#### Scenario: The stated cadence names what will run

- **WHEN** the effective policy is described to the operator, or an enabled policy
  is presented for confirmation
- **THEN** the description states the cadence in force — every hour for an
  hour-valued age, once a day at the named time for a day-valued age — and an
  hour-valued age's description does not name a time of day that does not run

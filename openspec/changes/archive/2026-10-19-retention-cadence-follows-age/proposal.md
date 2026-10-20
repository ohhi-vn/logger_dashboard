# Proposal

## Why

The scheduled retention task runs exactly once per day at the configured time of day. A policy whose retained age is expressed in hours (1h, 6h, 12h) therefore leaves rows far beyond that age in storage between runs: a "keep 1 hour" policy can hold up to a full extra day of logs until the next daily run fires. A daily cadence is right for day-valued ages, but a schedule that deletes at the granularity of the age it enforces should not be a day when the age is an hour.

## What Changes

- A retention policy whose retained age is expressed in hours runs **every hour, on the hour** (UTC). The configured time of day does not control those runs.
- A retention policy whose retained age is expressed in days keeps today's behavior: one run per day at the configured `run_at` time.
- Cadence is derived from the retained age rather than stored: the policy keeps its enabled / run-at / keep shape, and no stored-policy or configured-default format changes.
- The prune page's retention section follows the cadence in force: when an hour-valued age is selected the run-at field has no effect on the schedule, and the effective-policy description, the confirmation text, and the "next run" display state the cadence that will actually run.

Assumption recorded with the user: hour-valued ages run every hour (not "every N hours matching the age"), and hourly runs always fire on the hour rather than at the stored run-at time's minute. The retention vocabulary offers no minute-valued ages (its age presets are 1h, 6h, 12h, 1d, 3d, 7d, 30d, 90d), so there is nothing sub-hourly to schedule today; if minute-valued ages are ever added to the shared vocabulary, cadence can extend to them then. That extension is out of scope here.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `scheduled-retention`: the retention-policy requirement gains a derived cadence — an hour-valued retained age schedules hourly runs on the hour and the run-at time applies only to day-valued ages; the page must show the cadence actually in force rather than always implying a daily run.

## Impact

- `LoggerDashboard.Retention.Scheduler` — `next_occurrence/2` and `time_until_next/1` gain the hour-valued branch; the doc comments and module docs that describe "the next occurrence at the run time" need the cadence wording.
- `LoggerDashboard.Retention.Policy` — a pure cadence derivation from `keep`, and `describe/1` wording that states the cadence.
- Prune page retention section (`lib/logger_dashboard_web/live/prune_live/index.ex`) — the run-at input's role when an hour-valued age is selected, the section copy ("once a day without anyone watching"), and the "Next run" line.
- Tests: policy describe/build coverage and scheduler occurrence coverage for both cadences.

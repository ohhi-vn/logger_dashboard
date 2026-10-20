# Tasks

## 1. Policy: derived cadence and wording

- [x] 1.1 Add the pure cadence derivation to `LoggerDashboard.Retention.Policy` (design D1): map the unit of the `keep` age from `keep_options/0` to `:hourly` for `:hour`, `:daily` for `:day`, and fall back to `:daily` for any other unit. Verify: new tests in `test/logger_dashboard/retention/policy_test.exs` assert hourly for 1h/6h/12h and daily for 1d/3d/7d/30d/90d, plus the fallback.
- [x] 1.2 Make `Policy.describe/1` cadence-aware (design D3): an hour-valued age states "every hour" and names no time of day; a day-valued age keeps the existing "… at HH:MM UTC" wording; the disabled wording is unchanged. Verify: update the `describe/1` tests in `policy_test.exs` to one case per cadence and they pass (`mix test test/logger_dashboard/retention/policy_test.exs`).

## 2. Scheduler: hourly occurrence arithmetic

- [x] 2.1 Add the `:hourly` branch to `Scheduler.next_occurrence/2` (design D2): the next top-of-hour instant strictly after `now` (minute/second/microsecond zeroed, `+1 hour` when the boundary is not future); leave the `:daily` branch exactly as is. Verify: unit tests in `test/logger_dashboard/retention/scheduler_test.exs` cover both cadences, including a boundary case (an instant exactly on the hour schedules the next hour).
- [x] 2.2 Update the Scheduler's module doc and the "schedule" comments (design D2/D5) so the docs describe both cadences and keep the no-catch-up and no-drift rationale intact. Verify: the doc text matches the implemented behavior and `mix docs` (or a compile) runs clean.
- [x] 2.3 Add a scheduler-level test that an armed hour-valued policy schedules within the hour and does not catch up on boot (design D2): `time_until_next/1` under 1 hour for an hourly policy, and startup still dispatches nothing. Verify: the test passes in `scheduler_test.exs` without a real sleep.

## 3. Prune page: cadence-aware form and copy

- [x] 3.1 Make the retention form's run-at input render only when the currently selected keep is day-valued (design D4): add a `phx-change` on the retention form that re-derives the visibility from the submitted keep and persists nothing. Verify: `test/logger_dashboard_web/live/prune_live_test.exs` renders the run-at input for a day-valued keep and omits it for an hour-valued one.
- [x] 3.2 Apply design D4's carry-forward rule in `retention_apply`: when the submitted keep is hour-valued, carry the in-force policy's `run_at` forward instead of letting the absent field reset it to the default. Verify: a test asserting that arming an hour-valued policy leaves the previously held run-at time in the stored params, and that a day-valued submission still validates and stores its own run_at.
- [x] 3.3 Update the retention section copy (design D5): replace the "once a day" subtitle with cadence-neutral wording; confirm the in-force line, confirmation summary, and run log all read `Policy.describe/1` and therefore need no separate edit. Verify: LiveView tests assert the hourly wording for an hour-valued keep and the daily wording for a day-valued one, and the existing retention tests touched by the form change are updated and pass (`mix test test/logger_dashboard_web/live/prune_live_test.exs`).

## 4. Full verification

- [x] 4.1 Bring ClickHouse up and run `mix precommit`; fix any pending issue. Verify: the full suite and lint pass (`:clickhouse`-tagged tests included, per project context).

## Workflow follow-up

- After review, archive the change with `/opsx-archive` and verify the archived result.

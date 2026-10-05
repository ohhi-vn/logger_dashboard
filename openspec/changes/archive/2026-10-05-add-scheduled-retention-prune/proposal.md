# Proposal

## Why

Log retention is currently operator-driven only: someone opens `/prune`, previews a
scope, confirms, and the rows go. On a long-running ClickHouse install the table
grows until a human remembers to prune it, so unbounded growth is the default state
rather than a choice. Retention should be a policy the dashboard can hold and apply
on a schedule, not a chore that depends on someone noticing.

## What Changes

- **A retention policy the dashboard holds and applies unattended.** A scheduled
  prune deletes rows older than a configured age at a configured time of day,
  reusing the existing `:age` cutoff vocabulary rather than introducing a second
  one. The scheduled path composes `presets(:age)` → `Filter.parse/1` →
  `Prune.run/2` and adds no new SQL.
- **A durable default plus an editable runtime override.** The policy is configured
  through config/env and survives restart. The Prune page can edit the policy for
  the running system; that edit is an override held in memory, and a restart falls
  back to the configured default. Config is the floor, not the only source.
- **Explicit confirmation before unattended deletes are armed.** Enabling a
  scheduled policy is a destructive, recurring act, so it requires the same kind of
  explicit confirmation the manual prune already requires. Each unattended run logs
  the scope it acted on, so recurring deletes leave an audit trail.
- **No catch-up on restart.** A process that was down at the scheduled time waits
  for the next occurrence rather than deleting on boot, so a restart loop cannot
  cause repeated deletes.
- **`has_next` becomes exact.** The viewer currently infers "there is more" from
  `length(rows) >= limit`, which reports a next page on a full last page. It fetches
  one extra row instead and reports exactly what it knows.
- **`Prune.where_clause/2` drops its inert `scope` parameter.** `Prune.parse/1`
  already folds scope into the filter, so the argument is discarded with `_ = scope`
  and the signature overstates its dependency.

## Capabilities

### New Capabilities
- `scheduled-retention`: The system SHALL hold a retention policy comprising a
  run time, a retained age, and an enabled flag; SHALL apply it unattended at the
  configured time; SHALL require explicit confirmation before arming it; SHALL log
  each unattended run; SHALL fall back to the configured policy when the runtime
  override is absent (including after restart); SHALL NOT catch up a missed run on
  boot; and SHALL expose the effective policy and which layer supplied it on the
  Prune page.

### Modified Capabilities
- `log-viewing`: The last-page requirement becomes exact. A page holding exactly the
  per-page row count SHALL report no further pages when no further rows match, rather
  than inferring a next page from a full page. The row used to determine this is not
  displayed, so the page and its export are unchanged.
- `log-pruning`: Age-cutoff shortcuts widen to include hour-valued durations, because
  retention needs hour granularity and the shortcut vocabulary has a single owner that
  both surfaces draw from. A named duration resolves to the same cutoff on the manual
  age cutoff and on the scheduled retained age. Separately, the internal predicate
  builder stops accepting an inert scope argument; that is an implementation detail and
  changes no requirement text.

## Impact

- **New code.** A supervised scheduler process (the first non-Phoenix worker in this
  codebase), the retention policy state it owns, and retention controls on
  `LoggerDashboardWeb.PruneLive.Index`. No GenServer or ETS table exists today.
- **Reused, unchanged.** `LoggerDashboard.Logs.Filter` (`presets/1`, `parse/1`,
  `predicates/1`), `LoggerDashboard.Logs.Prune` (`run/2`), and the existing
  `:age` cutoff family. The scheduled path adds no SQL and no bound-parameter
  handling of its own.
- **Config surface.** New env/config keys for the policy default. They are read as a
  floor, so an unset key disables the feature rather than failing boot.
- **Safety surface.** Unattended deletes are the first destructive operation in the
  system with no human in the loop, and they cover whole-system scope. The
  confirmation gate and the per-run log are the compensating controls.
- **No new dependencies.** Scheduling uses OTP primitives already available; the
  runtime override needs no storage beyond the scheduler's own state.
- **No schema change.** No new table, and no DDL against the upstream-owned `logs`
  table.
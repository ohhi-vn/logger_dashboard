# Design

See `proposal.md` for the motivation and `specs/scheduled-retention/spec.md` (delta) for the required behavior.

## Context

The scheduler (`LoggerDashboard.Retention.Scheduler`) is a GenServer that recomputes
each occurrence from the wall clock: `next_occurrence/2` takes the policy's run time
(`{"HH:MM", zone}`), today's date at that clock time, and if that instant is already
past, adds a day. `handle_info(:run)` dispatches the delete and reschedules from the
new `now`, so the interval is structurally "once per day at run_at". The retained age
(`keep`) is an id from `Filter`'s `:age` family; `Policy.keep_options/0` already pairs
every id with its `{amount, unit}` duration, so the unit of the age is available
without any new vocabulary. `Policy.describe/1` renders the one-line description that
the in-force panel, the confirmation summary, and the run log all reuse. The page
("once a day without anyone watching") and the `Next run` line both read from the
scheduler's arithmetic.

## Goals / Non-Goals

**Goals:**

- Hour-valued retained ages (1h, 6h, 12h) schedule hourly runs, on the hour, in UTC.
- Day-valued retained ages keep the existing daily-at-run_at behavior, byte for byte.
- Cadence is derived, never stored: the policy's persisted shape (`enabled`, `run_at`,
  `keep`) is unchanged, and no store or config migration is needed.
- Every surface that names the schedule (in-force line, confirmation, run log, page
  copy, next-run display) states the cadence actually in force.

**Non-Goals:**

- No new cadence choices ("every N hours matching the age", minute-valued ages,
  cron-like expressions). If the shared age vocabulary ever gains a sub-hour unit,
  cadence can extend then; today's vocabulary has no such entry, so there is nothing
  to schedule sub-hourly.
- No change to the delete itself, the confirmation flow's safety properties, the
  no-catch-up-on-restart rule, or the store's behavior.

## Decisions

**D1 — Cadence is a pure derivation on `Policy`, not a stored field.**
`Policy` gains a `cadence/1` (name indicative) that maps the unit of `keep`'s
duration to `:hourly` for `:hour` and `:daily` for `:day`; any other unit falls back
to `:daily` (today's behavior) so an exotic future unit degrades safely instead of
raising. Alternative: add a fourth `interval` field to the policy struct. Rejected:
it widens the stored params and config format, needs migration handling, and creates
a contradicting state (hour-valued age, daily interval) the requirement forbids.
The derivation reuses `keep_options/0`, so it cannot disagree with the vocabulary
the form and scheduler already share.

**D2 — Hourly occurrence arithmetic stays wall-clock based.**
For `:daily`, `next_occurrence/2` is unchanged. For `:hourly`, it returns the next
top-of-hour instant strictly after `now`: today's date at minute 0, second 0,
microsecond 0, else `+1 hour`. The existing recompute-after-every-fire pattern
(`handle_info(:run)` → `schedule/1`) already yields hourly cadence from that, and
keeps the no-drift property the module docs justify. Alternative: a fixed
60-minute timer. Rejected: it drifts against the clock and after clock jumps — the
exact failure the current design documents against. `time_until_next/1` needs no
edit; it already routes through `next_occurrence/2`, which is why the page's
"Next run" line and the timer can never disagree.

**D3 — One description function stays the single source of cadence wording.**
`Policy.describe/1` branches on cadence: hourly policies read "keeping 1h, deleting
every node's logs older than that every hour" (no time of day named, because none
runs); daily policies keep the existing "… at 03:00 UTC" wording. Because the
in-force panel, the confirmation summary (`retention_confirm` stores
`Policy.describe(policy)`), and the run log all render this one function, all three
become cadence-accurate together, and no surface can claim a time of day that the
schedule ignores. The confirmation then states the cadence implicitly, which is the
operator-visible behavior the delta's "The stated cadence names what will run"
scenario pins.

**D4 — The run-at input is hidden for hour-valued ages, and the hidden value is
never clobbered.**
The page renders the run-at field only when the currently selected keep is
day-valued; selecting a keep re-derives that from params via a `phx-change` on the
retention form that persists nothing. The hazard hiding it creates: a submitted
form without the `run_at` key would validate `nil` run_at to the default
(`03:00 UTC`) and overwrite the operator's stored time — invisible while hourly,
wrong again the day they switch back. So `retention_apply` carries the in-force
policy's `run_at` forward when the submitted keep is hour-valued (and the policy
already has one), instead of letting the absent key reset it. Alternatives
considered: always render the field with an "applies to day-valued ages only" label
(zero plumbing, but a permanently visible control that does nothing); disable the
input (disabled inputs don't submit — same clobber hazard, plus a grayed control).
`build/1`'s validation is untouched: params still validate run_at whenever it is
present, including from config/env, so a stored day-valued policy stays fully
validated.

**D5 — Page copy states the cadence rather than "once a day".**
The section subtitle becomes cadence-neutral ("deletes logs older than the retained
age, across every node, without anyone watching, as often as the retained age
demands" — final wording at implementation). The `Next run` line needs no change;
it already renders `next_occurrence/2`.

## Risks / Trade-offs

- [An hourly policy dispatches 24 deletes per day instead of 1; ClickHouse sees more
  lightweight mutation requests.] → Each run is the same async delete the daily path
  uses, bounded to the same scope; the run log records every dispatch. Accepted as
  the requested behavior; operators opt in by arming an hourly policy through the
  existing confirmation.
- [Deploying this changes the behavior of already-stored hour-valued policies with
  no operator action.] → That is the requested fix; no format changes make the
  upgrade silent-but-visible: the in-force line names the new cadence, and rollback
  is a redeploy of the previous version.
- [Hidden run-at input could silently overwrite the stored run-at time with the
  default.] → D4's carry-forward rule; covered by a test asserting an hourly
  submission preserves the in-force `run_at` in the stored params.
- [Cadence derivation and `describe/1` could drift apart if someone adds a unit to
  the age family without touching either.] → Both live in `Policy` beside
  `keep_options/0`; the tests assert `describe` for one age per cadence and the
  "rejects every age preset as a retained age"-style exhaustive tests already exist
  to extend in the same file.

## Migration Plan

No migration: the stored params and config/env shape are unchanged, DDL is
untouched. Deploy the new code; day-valued stored policies behave identically,
hour-valued stored policies begin running hourly at the next occurrence. Rollback
is deploying the previous version; a stored policy's shape is readable by both.

## Open Questions

None. The two material choices (hourly cadence for hour-valued ages; on-the-hour
runs with run-at ignored) were answered by the operator before planning.

# Design

## Context

See `proposal.md` — Why for motivation and `specs/` for requirements.

Constraints that shape the approach, none of which are negotiable within this repo:

- **No database but ClickHouse, and its DDL is upstream.** `openspec/config.yaml`
  records that DDL stays upstream (`mix clickhouse_ex_logger.migrate`) and that the
  dashboard never migrates. There is no Postgres. Any design that needs durable
  per-operator state has to either add storage or not need it.
- **Raw SQL is the sanctioned escape hatch**, and `LoggerDashboard.Logs.Prune` and
  `LoggerDashboard.Logs.LogRead` are its established users. Text predicates cannot be
  pushed down through Ash in this version, so anything the scheduler does must route
  through `Filter.predicates/1` and never through an Ash filter on `message`.
- **Every process in this codebase is a Phoenix request.** There is no GenServer, no
  ETS table, no Agent, and no supervision-tree worker outside `Telemetry` and the
  `Endpoint`. A scheduler is the first supervised worker, and it is the first thing
  that outlives a request.
- **The `:age` family is already the vocabulary for retention-shaped cutoffs.**
  `Filter.presets(:age)` exists and its doc names the prune page as its consumer.
- **Manual prune is deliberately paranoid**, and its guardrails are load-bearing:
  `Prune.parse/1` requires an explicit scope, rejects a multi-node value so a
  confirmation cannot understate the blast radius, and `require_bounds/1` refuses an
  unbounded delete with no override. Scheduled pruning has none of those human
  checks, so it inherits none of their protection.

## Goals / Non-Goals

**Goals:**

- Keep scheduled retention to OTP primitives and one supervised process. No new
  dependency, no new table, no new storage subsystem.
- Make the scheduled path a *composition* of existing functions rather than a parallel
  implementation, so retention cannot drift from manual pruning's safety behaviour.
- Make the "which policy is in force, and will it survive a restart" question
  answerable from the UI, because that is the question an operator will actually ask.

**Non-Goals:**

- Per-node retention schedules. One system-wide policy; see below.
- Catch-up semantics, dry-run runs, or a preview of what an unattended run would
  delete. A scheduled run has no human in the loop, so a preview UI for it would be
  theatre.
- Backfilling or replaying missed occurrences.
- Changing the manual prune flow's guardrails.

## Decisions

### D1. Configured default is the floor; the UI edit is an in-memory override

**Decision.** The retention policy is read from config/env at boot and is the
effective policy whenever no override is present. Editing it on the prune page stores
an override in the scheduler's own state. It is never written back to config.

**Rationale.** This is the only layering that satisfies "config/env for the schedule,
editable, but fall back to the default on restart" without the dashboard writing its
own configuration. It also keeps the repo's core premise intact: no new persistence,
so nothing to migrate, back up, or reconcile.

**Alternative considered — a table in ClickHouse.** Rejected. It would make the
schedule durable *and* editable, but it means creating a table in a database whose DDL
this project explicitly does not own, and ClickHouse is an OLAP engine with no
natural upsert — it is a poor fit for mutable single-row configuration. The cost
breaks the premise that the dashboard reads only ClickHouse's `logs` table.

**Alternative considered — persist by rewriting config at runtime.** Rejected
outright: writing into a baked release or a read-only container filesystem is not
something a dashboard should attempt, and failing silently on a read-only mount would
be worse than the override expiring.

### D2. The override lives in the scheduler's state, not a separate ETS table

**Decision.** The scheduler is a `GenServer` and the override is a field in its
state, read with a `GenServer.call`. No ETS table is created.

**Rationale.** The override has exactly one reader class (the LiveView) and one
writer (the same LiveView), and it must not outlive the process that owns it. The
scheduler is already a supervised, uniquely-named process holding this state, so a
separate ETS table would add a second owner and a supervision entry to express
something the first process can already hold. `LoggerDashboardWeb.PruneLive.Index`
reads the effective policy through the scheduler rather than reaching for storage.

**Alternative considered — an ETS table owned by a dedicated process.** Rejected: a
separate owner is needed only when the state must outlive a crash or be shared across
independently-supervised processes. Neither applies; the override is *supposed* to die
with the runtime.

### D3. Scheduled retention composes the existing age-cutoff path

**Decision.** A run resolves the retained age to a cutoff, builds a filter from it, and
calls the existing `Prune.run/2`. There is no new SQL and no new predicate builder.

**Rationale.** `presets(:age)` → `Filter.parse/1` → `Prune.run/2` already means
"delete everything older than N". The scheduled case differs only in *who* calls it
and *when*. Reusing it means the scheduled path inherits bound-parameter handling and
the age-cutoff semantics for free, and it cannot develop its own idea of what
"older than 7 days" means. Note that `require_bounds/1` is satisfied by construction
here, since an age cutoff always sets an upper bound — so retention does not need its
own unbounded-delete guard.

**Alternative considered — a dedicated `Retention.delete/1` issuing its own
`ALTER TABLE ... DELETE`.** Rejected: it would duplicate predicate construction that
already has one owner, and would be a second place to get bound parameters wrong.

### D4. Hour granularity extends the `:age` family rather than adding a vocabulary

**Decision.** Retention offers hours and days. Rather than a retention-specific
vocabulary, the `:age` preset family gains hour-valued entries, and both the prune
page's age shortcuts and retention draw from it.

**Rationale.** `Filter.presets/1` already exists to be "the single owner" of this
vocabulary, and its consumers render it rather than restating it. A second vocabulary
would reintroduce exactly the drift the module was written to prevent, and would leave
an operator unable to express "older than 6 hours" on the prune page while retention
could.

**Consequence, stated plainly.** The prune page's age shortcuts widen as a side effect,
so `log-pruning`'s requirement that enumerates the offered shortcuts changes. That is a
real behaviour change to an existing capability and carries its own delta. The
alternative — leaving manual age cutoffs day-only while retention accepts hours — was
rejected as an inconsistency an operator would trip over.

### D5. No catch-up, ever

**Decision.** The scheduler computes the next occurrence from the wall clock at each
recompute and fires then. It never runs the policy on boot because an occurrence was
missed.

**Rationale.** Catch-up converts a restart into a delete. A dashboard that crash-loops
or is being redeployed would fire a delete on every boot, and the operator has no way
to see it happen. Refusing to catch up makes the failure mode "the schedule slipped",
which is visible and harmless, rather than "the table lost data repeatedly", which is
not.

**Alternative considered — catch up once on boot.** Rejected for the loop above. A
narrower variant that catches up only when the missed occurrence is recent (say, within
the retention period) still deletes on boot for the crash-loop case, so it buys little.

### D6. Confirmation gates arming, not each run

**Decision.** Enabling a schedule requires an explicit confirmation stating the
resolved scope and retained age. Once armed, subsequent runs need no further prompt;
each run is logged instead.

**Rationale.** The confirmation protects the moment where a recurring, unattended,
irreversible delete is *authorised* — which is the decision that deserves a human. It
would be poor design to make an operator confirm the same thing nightly, and worse to
leave the actual deletion with no trace. So the gate is on arming and the audit trail
is on each run. These are complementary: the gate answers "did a human authorise
this?", the log answers "what did it actually do?".

**Alternative considered — confirm every run.** Rejected: nobody would leave it
enabled.

### D7. `has_next` is determined by an extra row, not by a full page

**Decision.** The viewer fetches `limit + 1` rows, keeps the first `limit` for display,
and derives whether further pages exist from whether the extra row was present.

**Rationale.** The current `length(rows) >= filter.limit` cannot distinguish "the last
page happens to be exactly full" from "there is more", so a total that is an exact
multiple of the page size ends on a full page that still offers Next, leading to an
empty final page. One extra row makes the answer exact for the cost of one row, and
the row is never displayed — `page_rows` remains the display list, so the export still
covers exactly what is shown, which is what the export requirement demands.

### D8. The undecodable-format invariant is documented, not defended with a dependency

**Decision.** Do not add `nimble_csv`. Instead, record the invariant that raw reads
must resolve to a decodable format, and keep the existing `nil`-rows-as-error
handling.

**Rationale.** `nimble_csv` is declared `optional: true` by the driver and is absent,
so `ClickHouse.Format.TSV` and its siblings are not compiled at all — only
`JSONCompactEachRow`, `RowBinary`, and `Values` are. The supported path is covered
because `AshClickhouse.Connection` pins `default_format = "JSONCompactEachRow"`, and
that is the format the raw read path already relies on. Adding the dependency would add
three decoders this project never uses and change no behaviour.

The branch in `LogRead.handle_result/1` that turns a `nil` rows field into an error
stays, and is *more* clearly justified by this: it is what converts a format the
driver cannot decode into a visible failure instead of a log viewer that looks empty.
That guard is load-bearing, not dead code.

**Alternative considered — pin `default_format` explicitly at the repo config.**
Worth revisiting only if a future driver change ever moves that default; today it is
already guaranteed by the data layer and adding it would be duplication.

### D9. Multi-instance firing is accepted

**Decision.** Do not add leader election or a distributed lock.

**Rationale.** The delete is a cutoff on `timestamp`, so it is idempotent: two
instances firing the same policy delete the same rows and the second is a no-op. The
cost is a redundant mutation, not incorrect behaviour. Leader election would add real
machinery — and real storage — to prevent a harmless duplicate. The limitation is
documented instead. This is the one place where the design knowingly accepts a wart.

## Risks / Trade-offs

- **An unattended whole-system delete has strictly less protection than a manual one.**
  Manual prune rejects an unbounded delete, rejects multi-node scope, and previews the
  resolved predicate. A scheduled run has none of those. → Mitigation: the run is
  always a bounded age cutoff by construction, so the unbounded-delete hazard cannot
  arise; arming is confirmed (D6); every run is logged (D6). Accepted knowingly: the
  schedule covers strictly more ground than the manual path it mirrors.

- **A misconfigured retained age deletes far more than intended.** A "keep 1h" typo
  instead of "keep 1d" prunes 24x the intended volume, unattended. → Mitigation: the
  confirmation states the resolved cutoff; the retained age draws from a fixed
  vocabulary rather than free text, which removes the typo class; every run is logged.

- **The override silently disappearing on restart could surprise an operator** who
  edited the policy, saw it take effect, and assumed it was now the policy. →
  Mitigation: the prune page shows the effective policy and identifies its source as
  either the configured default or an override that will not survive a restart. The
  behaviour is stated in the spec so it cannot be quietly treated as a bug.

- **The scheduler is the first supervised worker and the first stateful long-lived
  process; a crash loop in it would restart-loops the supervisor.** → Mitigation: it
  must not perform a delete in `init/0` — no catch-up (D5) means startup is inert;
  supervise it `:one_for_one` alongside `ClickhouseExLogger.Repo`, which it depends on,
  so a repo restart does not take the scheduler with it.

- **Wall-clock scheduling across a DST transition or a container clock jump fires at an
  unexpected time.** → Mitigation: resolve each occurrence against UTC, which is what
  the rest of this project already uses for log timestamps and filter bounds, and
  recompute the next occurrence after each fire rather than sleeping a fixed interval —
  so a clock jump self-corrects on the next recompute instead of drifting indefinitely.

- **Widening the `:age` family changes the manual prune page's shortcut set** as a
  side effect of D4, which is more change than the feature strictly requires. →
  Mitigation: it is carried as an explicit delta on `log-pruning` rather than left as
  an undeclared side effect, and it is one shared vocabulary instead of two.

- **`Prune.where_clause/2` loses a parameter it had always accepted.** Any caller
  outside this repo passing `scope` would break. → Mitigation: it is
  `@doc false`, so it is not public surface; a compile error is the intended outcome
  for an internal signature that lied about its dependency.

## Migration Plan

No data migration. Nothing to backfill. Deployment order:

1. Ship the code with the feature unconfigured. Unset retention config means the
   feature is off, so a deploy that precedes configuration cannot start deleting.
2. Configure the policy default (enabled flag, run time, retained age) and restart.
3. Optional: edit the policy from the prune page, understanding the edit is an
   override that a later restart will discard in favour of step 2's configured value.

Rollback: unset the configured policy and restart. This disables scheduled pruning
without touching the code, and without affecting manual pruning, the viewer, or
analysis. Already-deleted rows are not recoverable — the delete was async and
irreversible — which is a property of ClickHouse mutations generally and is why
rollback is about stopping future deletes, not undoing past ones.

The two viewer/prune fixes are independent of all of the above and can ship or revert
on their own; neither depends on the scheduler.

## Open Questions

- Whether hour-valued age entries should be *ordered* so the prune page's shortcut row
  stays shortest-first as the `:age` doc requires. This is a presentational detail
  within D4's settled approach; it does not change the specs or the task breakdown.
- Whether the per-run log line should go through `Logger.info/1` only, or also be
  retained in a small ring the Prune page could display as "last run". The latter would
  need a new surface and is deliberately out of scope here; if wanted it is a separate
  change rather than an extension of this one.
# Design

## Context

See proposal.md — Why for motivation.

What shapes the approach:

- The archived change that introduced scheduled retention recorded three decisions
  this one reverses: the configured default is a floor rather than the only source
  (D1), the override lives in scheduler state and not a separate table (D2), and
  "no new dependency, no new table, no new storage subsystem" (design goal). D1 and D2
  are now wrong; the storage goal is narrowed to "no server, no DDL" rather than
  dropped.
- `LoggerDashboard.Retention.Scheduler` is currently the sole owner of the effective
  policy. `effective/1` and `override_source/1` are two private functions over one
  `%{override: ...}` field, and `Policy.resolve/1` is the parallel pure version used
  only by the moduledoc's story.
- `Retention.Policy` already owns validation and vocabulary (`Filter.presets(:age)`),
  and `Policy.build/1` already rejects an unusable retained age with a message. That is
  the validation the store needs on read; it does not need new validation logic.
- `application_test.exs` asserts the scheduler's position in the supervision tree
  (after `ClickhouseExLogger.Repo`, before the endpoint). Anything new in the tree
  needs a place relative to both.
- The release runs as `nobody` with `WORKDIR /app` and `chown nobody /app`, so a
  writable path exists by default. The dashboard's compose service mounts no volume;
  `clickhouse-data:/var/lib/clickhouse` is the only one.
- CUB requires exactly one process per data directory. That is a hard constraint on
  supervision, not a preference.

## Goals / Non-Goals

**Goals:**

- Replace the in-memory override with a durable, task-keyed store that one supervised
  process owns.
- Keep the store ignorant of retention. Retention supplies its own validator and its
  own vocabulary; the store supplies read, write, clear, and a way to report failure.
- Keep the boot path inert. A durable policy must not become a durable obligation to
  delete.
- Make store failure non-fatal to the dashboard, and visible when it happens.

**Non-Goals:**

- Cross-instance coordination. Each instance keeps its own store and its own schedule.
- Leader election, advisory locks, or any attempt to make two instances agree.
- A general configuration surface. Retention is the only key; nothing here adds a
  settings page, a config editor, or a second task.
- Compaction tuning, snapshots, or `CubDB` transaction usage. One key, one value, read
  on page load and at boot.
- Backfilling a stored policy from the configured default. An empty store stays empty.

## Decisions

### D1: One CUB instance, owned by a supervised process, keyed by task

`CubDB.start_link(data_dir: ...)` runs as a child of `LoggerDashboard.Supervisor`,
registered so exactly one instance can hold the directory. CUB's own docs require a
single process per directory; putting it in the tree makes that structural rather than
a convention, and a release restart brings it back in the right order.

The store is one module, `LoggerDashboard.BackgroundTaskConfig`: it owns the `CubDB`
process and exposes the task-keyed `get/2`, `put/3`, and `delete/2` over a
`{module, key}` namespace. The namespace is what keeps one task's value from being
readable as another's; CUB keys are arbitrary terms, so a namespaced tuple is enough
and no schema is needed. Two modules — a task-facing one over a store-facing one —
was the original sketch; it left a layer that only forwarded three calls to the module
below it, so it was collapsed into the one that has to exist anyway.

Writes are single-key `CubDB.put/3`, not a transaction. A transaction would be
meaningless for one key and would trade away MVCC's non-blocking reads for nothing.

*Alternative considered*: use `CubDB` directly from `Scheduler` and from the LiveView,
keyed by `:retention`. Rejected — it makes retention the store's schema, so the second
background task means either a retrofit or a second store, and it spreads a
persistence concern across a process and a LiveView.

*Alternative considered*: let the LiveView `start_supervised!` a CUB instance per mount.
Rejected — CUB forbids two processes on one directory, and per-mount instances would
race the supervised one.

### D2: The store reports failure as a value, and never raises to the caller

Every operation returns `{:ok, ...}` / `{:error, reason}`; nothing rescues into a
silent `nil`. The dashboard boots regardless: the supervised child's failure is logged
and the store module's calls answer `{:error, reason}`, which tasks translate into
their configured default plus a surfaced message.

This is the one place where the existing `Policy.from_config/1` behaviour — forgiving
at boot, strict at the edge — does *not* transfer. A mistyped env var should not stop a
dashboard from booting; a store that cannot be opened also must not. But neither may be
invisible: an operator whose saved policy silently stopped applying would have no way
to know, which is strictly worse than the restart-loss wart this change removes.

*Alternative considered*: let the CUB child crash the supervisor, since `:one_for_one`
restarts it. Rejected — it converts a persistence problem into an availability
problem, and the app has no reason to stop serving `/logs` over it.

### D3: Retention validates on read; the store stores what it was given

`Scheduler` gains a load step: read the stored params, run them through
`Policy.build/1`, and treat `{:error, reason}` as "no usable stored policy" — fall back
to `Policy.configured()` and record the reason so the page can show it. The stored
value is left untouched in that case.

`Policy.build/1` is already the right validator: it rejects an age outside
`Filter.presets(:age)` with a message naming the accepted ids. Reusing it means the
stored-value validation and the form validation cannot disagree about what a valid
policy is, which is the property that made `keep` a named id in the first place.

*Alternative considered*: validate on write only, and trust the store on read. Rejected
— the store is a file an operator can edit, and a `keep` that no longer resolves would
otherwise reach `Filter.resolve_preset/2` at delete time.

### D4: `Scheduler.init/1` loads the stored policy and stays inert

`init/1` reads the stored policy (or the configured default), calls the same
`schedule/1` it calls today, and returns. No delete runs on boot. This is unchanged
behaviour, and it is unchanged for a reason that this change strengthens rather than
weakens: a durable policy is now *always* there after the first save, so if boot
caught up, every restart in a crash loop would delete.

The `override` field becomes `policy` and is always populated; `effective/1` and
`override_source/1` collapse into it. `Policy.resolve/1` and its
`:config | :override` source become `:configured | :stored` — the source is now
"where did this come from" rather than "how long will this last", and the page's job
changes accordingly.

`effective_policy/1` answers a report rather than a `{policy, source}` pair: a stored
policy the process cannot use, and a store it could not read, are both things the page
has to be able to say, and neither fits in a source atom.

That leaves one gap worth naming: a process that loaded its policy at boot would
otherwise keep a stale policy and a stale error for its whole life, which would make
the store's deliberately uncached failure reporting pointless. So the scheduler also
grows `reload/1` — re-read and reschedule — and the page uses the store's status
rather than anything cached, so a repaired directory is usable again without a
redeploy.

*Alternative considered*: keep two layers in memory (load stored into the override
field, fall back to config) so `effective/1` keeps its shape. Rejected — it keeps a
distinction the system no longer makes.

### D5: `set_override/2` and `clear_override/1` stay the scheduler's public API

The scheduler keeps owning "the policy in force" and the timer. `set_override/2`
writes to the store then reschedules; `clear_override/1` deletes the stored value then
reschedules. The LiveView does not learn the store exists.

Write-then-reschedule is ordered deliberately: if the store write fails, the schedule
is not changed, so the page shows an error rather than arming something it could not
persist. That ordering is the difference between "your edit did not save" and "your
edit works until the next restart".

*Alternative considered*: have the LiveView write to the store directly and then call
`set_override/2` with the policy. Rejected — two writers, and a partial failure could
persist a policy the scheduler never armed.

### D6: The confirmation gates the write and the arming, not just the arming

Writing an enabled policy *is* arming it — the write and the timer come from the same
call, in that order. So `retention_apply` writes nothing for an enabled policy: it
validates, keeps what the operator typed, and opens the confirmation. Only
`retention_confirm` calls `set_override/2`, which writes and then reschedules.
"Confirmed" and "armed" therefore cannot come apart, and an unconfirmed policy exists
nowhere — not on disk, not in force, not pending.

This is also the correction of a pre-existing gap. The previous two-step flow wrote the
override on submit and armed the timer there too, so the confirmation only ever
prevented an immediate delete and never the next scheduled one. In-memory that was
bounded by the next restart; with a durable store it would have been bounded by
nothing but a revert.

A disabled policy is written without the confirmation, and removing the saved policy
already was. Both delete nothing and arm nothing, so gating them would put friction
only on the urgent direction — stopping a policy you regret — and a durable store
removed the restart that used to be the escape hatch. Confirmation is permission to
delete unattended; nothing else needs it.

The separate "Arm…" button went with the merge: submit is now the only way to propose
a policy, so a second button that reopened the same panel had no reason to exist.

*Alternative considered*: write on submit and let the confirmation only re-affirm, the
old behaviour. Rejected — the timer is armed by the write, so this is not a stronger
gate, it is the same gate one step later.

*Alternative considered*: require confirmation for disabled policies too, for one
uniform rule. Rejected — it would make stopping a running system-wide delete a
three-click operation with no other escape, to protect against a delete that cannot
happen.

### D7: The store directory is a runtime variable, defaulting inside the release

`runtime.exs` reads `TASK_CONFIG_DIR` (or similar), defaulting to a path inside the
release. `config.exs` points dev/test at per-environment directories under `tmp/`, so
tests never share a store with a running dev instance or with each other.

Dev/test paths matter more than they look: several existing tests save-and-restore
application env around the retention config, and the new equivalent needs a directory
per test rather than a shared one, or tests will observe each other's stored policies.

The compose stack adds `task-config-data:/var/lib/logger_dashboard` mounted at the
configured path, plus the variable in `.env.example`.

*Alternative considered*: derive the directory from the release's own `data_dir` with
no variable. Rejected — a fixed internal path cannot be mounted by an operator, so the
compose volume would have nothing to point at.

### D8: Per-instance divergence is documented, not solved

CUB is a local DETS file. Two dashboard instances each hold their own policy and each
fire their own deletes at ClickHouse. That was already true before this change (two
instances each read the same configured default and each fired); what changes is that
the policies can now differ.

The dashboard is documented and deployed as a single instance. Leader election would
mean a lock the CUB API does not provide, a shared directory, and a new failure mode
where nobody prunes because the lock is stale. Not worth it for a single-instance
deployment; recorded in the compose-deployment docs and in the prune page's source line
instead.

## Risks / Trade-offs

- **A stored policy outlives the code that understands it.** A `keep` id removed from
  `Filter.presets(:age)` would leave a stored policy that validates as unusable.
  → Mitigated by D3: it falls back to the configured default and says so on the page,
  and the stored value is preserved for inspection. This is a behaviour change worth
  calling out to operators — a policy that used to keep deleting may stop.

- **A broken store silently disables saving, and the operator may not notice.** The
  page shows the error, but only while someone is looking at it.
  → Mitigated by logging the failure at boot and on every failed operation, and by
  showing the store's status in `#retention-effective` so the page never claims a
  policy is stored when the store is down.

- **Durability raises the cost of a bad edit.** Previously a bad policy died with the
  process; now it survives until reverted, including across a redeploy.
  → Accepted deliberately — that is the point of the change. The arm/confirm gate
  (D6) is the control that makes a stored policy authorised rather than merely saved,
  and reverting is a single explicit action.

- **An existing deployment that relies on override-loss now keeps its override.** After
  this change, a deployment that edited the policy at runtime will find that edit still
  in force after its next restart, where previously the configured default returned.
  → Called out in the migration plan. It is a one-line revert from the prune page.

- **Corrupt store file.** CUB is designed not to corrupt on crash, but a truncated or
  hand-edited file is possible.
  → Mitigated by D2: an unreadable store is an error, the dashboard still serves, and
  the fix is to delete the directory — which is also what `down --volumes` does.

## Migration Plan

1. Land the dependency, the store, and the directory configuration. At this point the
   store is written to and read from, but `Scheduler` still resolves from memory, so
   behaviour is unchanged.
2. Switch `Scheduler` and the prune page to the store. Existing deployments pick up the
   new precedence on next boot: an empty store means the configured default is in
   force, which is what was already true.
3. Deploy the compose volume and the environment variable. Until an operator mounts it,
   the store lives in the container's writable layer and survives an application restart
   but not a container recreate — degraded, never wrong.
4. Rollback: revert to the previous image. A stored policy left in the volume is simply
   ignored by an older release, which reads config only. No data migration, and nothing
   to undo in the volume.

## Open Questions

None. The remaining choices — precedence, durability, divergence — were settled before
writing the specs, and each is pinned by a requirement in
`specs/background-task-config/spec.md` and `specs/scheduled-retention/spec.md`.
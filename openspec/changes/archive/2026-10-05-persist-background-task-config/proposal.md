# Proposal

## Why

Scheduled retention is the one feature here that deletes data with nobody watching,
and today its operator-facing configuration is deliberately ephemeral: the policy
edited on the prune page lives in the scheduler process's memory, is silently
discarded on restart, and is described in the spec as "an override that will not
survive a restart". That was the right call when there was no writable place to put
it. The compose stack now provides one, so the constraint has moved and the behaviour
should move with it: an operator who arms a system-wide delete should not discover
from a log line that their policy reverted during last night's deploy.

CUB gives the dashboard a durable, embedded, single-file key-value store with no new
server and no DDL, which is the constraint this project has been honouring all along
(it does not own the ClickHouse schema either).

## What Changes

- Add `cubdb` as a dependency and start a single `CubDB` instance in the supervision
  tree, backed by a configurable data directory.
- Add a general background-task configuration store keyed by task name. Retention is
  the first and only key today; the module does not know what retention is.
- The retention policy edited on the prune page is written to that store instead of
  held in scheduler memory. It now survives an application restart.
- The stored policy takes precedence over the application-environment default. The
  configured default is now the seed used when the store holds nothing, not a
  competing layer.
- The prune page reports the stored policy's persistence instead of warning that an
  edit is lost on restart, and "revert" now deletes the stored value.
- Startup remains inert: no delete runs on boot to catch up, and a stored policy is
  not re-armed without a fresh confirmation if the dashboard was not running when the
  scheduled time passed. The store makes the policy durable; it does not make the
  schedule retroactively true.
- The store is per-node. Two dashboard instances each keep their own copy and each run
  their own schedule. This is documented rather than solved.
- Add a named volume to the compose stack and an environment variable for the store
  directory, so stored configuration survives container recreation, not merely
  application restart.

## Capabilities

### New Capabilities
- `background-task-config`: durable storage for the configuration of the dashboard's
  background tasks — what the store guarantees (persistence, precedence over the
  environment default, validation on read), how a task registers a key, and what
  happens when the store is unavailable or holds an unusable value.

### Modified Capabilities
- `scheduled-retention`: the runtime override becomes a persisted value that survives
  a restart and outranks the configured default; the configured default becomes the
  seed for an empty store; the page reports the stored value's source rather than
  warning that an edit will vanish.
- `compose-deployment`: a named volume carries the dashboard's configuration store
  across container recreation, alongside the existing ClickHouse data volume.
- `container-image`: the release gains an environment variable naming the store
  directory, and the image provides a writable path for it owned by the runtime user.

## Impact

- **Dependencies**: `{:cubdb, "~> 2.0"}`, added to `mix.exs`.
- **New modules**: `LoggerDashboard.BackgroundTaskConfig.Store` (the CUB-backed
  store) and `LoggerDashboard.BackgroundTaskConfig` (task-keyed accessors). Neither
  references retention; the retention module keeps its own vocabulary.
- **Changed modules**:
  - `LoggerDashboard.Retention.Scheduler` — reads its policy from the store at `init/1`
    instead of starting from `%{override: nil}`; `set_override/1` and `clear_override/1`
    become store writes.
  - `LoggerDashboard.Retention.Policy` — `resolve/1` and its `:config | :override` source
    become `:configured | :stored`.
  - `LoggerDashboardWeb.PruneLive.Index` — the source line in `#retention-effective`
    no longer warns about restart loss; `#retention-reset` deletes the stored value.
  - `LoggerDashboard.Application` — the `CubDB` child starts before the scheduler.
- **Configuration**: `config/runtime.exs` reads a new store-directory variable;
  `config/config.exs` and `config/test.exs` point it at a per-environment directory so
  tests never share a store.
- **Deployment**: `compose.yaml` gains a named volume for the store directory and
  documents the variable; `.env.example` gains the variable; `Containerfile` gains the
  writable directory.
- **Tests**: the assertions that encode the old decisions are replaced, not preserved —
  `scheduler_test.exs`'s no-ETS and in-state checks, `scheduler_test.exs`'s
  restart-stand-in, and `prune_live_test.exs`'s "saving an edit writes no configured
  value". New tests cover store precedence, an unreadable value, and an unavailable
  store.
- **Not changed**: the delete path. `Prune` remains the only author of
  `ALTER TABLE ... DELETE`, `Filter.predicates/1` remains the only predicate builder,
  `Filter.presets(:age)` remains the only duration vocabulary, and the confirmation
  gate still guards arming rather than each run.
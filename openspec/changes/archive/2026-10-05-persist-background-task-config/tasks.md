# Tasks

## 1. Dependency and configuration

- [x] 1.1 Add `{:cubdb, "~> 2.0"}` to `mix.exs` and verify `mix deps.get` resolves and
  `mix compile --warnings-as-errors` succeeds
- [x] 1.2 Add the store-directory configuration to `config/config.exs` (dev and test,
  under `tmp/`, distinct per environment) and to `config/runtime.exs` (reading the
  release environment variable, defaulting inside the release directory); verify the
  directory is not shared between `mix phx.server` and `mix test` by asserting on
  `Application.get_env(:logger_dashboard, :task_config_dir)` in a test
- [x] 1.3 Update the retention comments in `config/runtime.exs` and `config/config.exs`
  that describe the configured value as a floor returned on restart, and verify the
  comments now describe it as the value used until something is stored

## 2. The store

- [x] 2.1 Create `LoggerDashboard.BackgroundTaskConfig` owning a single `CubDB`
  process: start, and `get`/`put`/`delete` over a `{module, key}` namespace, each
  returning `{:ok, value}` / `{:error, reason}`; verify no operation raises for an
  unstarted or failed store. One module rather than the two sketched in design.md D1:
  the split left a delegating layer with no callers of its own
- [x] 2.2 Make store startup non-fatal: an unwritable or missing directory yields a
  logged failure and an `{:error, reason}` from every operation rather than a crashed
  child; verify with a store pointed at a path under a read-only or non-existent parent
- [x] 2.3 Add `test/logger_dashboard/background_task_config_test.exs` covering
  round-tripping an arbitrary term, per-task key isolation, clearing one task leaving
  others intact, and a read that does not modify the stored value; verify with
  `mix test test/logger_dashboard/background_task_config_test.exs` using a per-test
  directory
- [x] 2.4 Add cases to `test/logger_dashboard/background_task_config_test.exs` for an
  unopenable store and for a corrupt store file; verify both answer `{:error, reason}`
  and log, and that neither takes down the calling process

## 3. Supervision

- [x] 3.1 Start the store's `CubDB` child in `LoggerDashboard.Application` before the
  retention scheduler and extend `test/logger_dashboard/application_test.exs` to assert
  the ordering relative to both `ClickhouseExLogger.Repo` and the scheduler; verify the
  supervisor starts with the store's directory unset, unwritable, and valid

## 4. Retention reads and writes the store

- [x] 4.1 Change `Retention.Policy.resolve/1` and its `source` type from
  `:config | :override` to `:configured | :stored`, and verify `mix compile` reports no
  remaining callers of the old atoms
- [x] 4.2 Change `Retention.Scheduler`'s state from `%{override: ...}` to a populated
  `%{policy: ...}` plus the reason a stored value was unusable; load it in `init/1`
  through `Policy.build/1` and fall back to `Policy.configured()` on an unusable stored
  value, leaving the stored value in place; verify `:sys.get_state/1` shows the loaded
  policy and the fallback reason
- [x] 4.3 Make `Scheduler.set_override/2` write to the store before rescheduling and
  leave the schedule untouched when the write fails; verify with `:sys.get_state/1`
  that a failed write leaves both the stored value and the timer as they were
- [x] 4.4 Make `Scheduler.clear_override/1` delete the stored value and then reschedule;
  verify the stored value is gone from the store and the configured default is in force
- [x] 4.5 Replace the assertions in `test/logger_dashboard/retention/scheduler_test.exs`
  that encode the removed decisions — the no-ETS check, the "override lives in scheduler
  state" check, and the `init/1` restart stand-in — with ones covering store precedence,
  survival across a restart of the store, and an unusable stored value falling back to
  the configured default; verify `mix test test/logger_dashboard/retention/scheduler_test.exs`
  passes without a running ClickHouse
- [x] 4.6 Keep `Scheduler.init/1` dispatching no delete, and add a case proving that a
  stored enabled policy still produces no delete on boot after a missed occurrence;
  verify the case asserts absence of the `[retention] unattended prune` log line
- [x] 4.7 Leave `Policy`, `Filter`, and `Prune` untouched; verify the composition
  assertions already in `scheduler_test.exs` and `prune_test.exs` still pass unchanged

## 5. The prune page

- [x] 5.1 Rewrite the `#retention-source` copy in `PruneLive.Index` to state that a
  stored policy survives a restart, and to show the reason a stored policy is not in
  effect when there is one; verify by rendering the page with an unusable stored value
  and asserting on `#retention-source`
- [x] 5.2 Change `#retention-reset` to say it removes the stored policy and returns to
  the configured default, and show a store failure in `#retention-error` when a write
  fails; verify with `render_click` on `#retention-reset` and on `#retention-confirm-button`
- [x] 5.3 Show the store's availability in `#retention-effective` so the page never
  claims a policy is stored while the store is down; verify by pointing the store at an
  unopenable directory and asserting the element reports the failure
- [x] 5.4 Update `test/logger_dashboard_web/live/prune_live_test.exs`: replace "saving an
  edit writes no configured value" and "revert returns to `:config`" with cases
  covering persistence through the store, `:configured` / `:stored` reporting, and
  revert deleting the stored value; verify
  `mix test test/logger_dashboard_web/live/prune_live_test.exs` passes
- [x] 5.5 Keep the arm/confirm gate intact: assert `retention_arm` still writes nothing
  and deletes nothing, and that `retention_confirm` still writes; verify via the
  existing `#retention-arm` / `#retention-confirm-button` cases plus a store read after
  arming

## 6. Deployment

- [x] 6.1 Add the store directory to the `Containerfile`'s runner stage, owned by the
  runtime user; verify the image builds with `podman build` and the release creates and
  writes the default directory as `nobody`
- [x] 6.2 Add a `task-config-data` named volume to the dashboard service in
  `compose.yaml`, mounting it at the configured directory, and add the directory
  variable to `.env.example` noting the volume backing; verify `podman compose config`
  resolves and the stack still declares only the dashboard and ClickHouse services
- [x] 6.3 Document the store, the directory variable, the per-instance divergence, and
  the revert step in `README.md`; verify the documented commands match
  `compose.yaml` and `.env.example` as written

## 7. Verification

- [x] 7.1 Run `mix precommit` with a ClickHouse available and fix any failures,
  including the existing `:clickhouse`-tagged tests this change does not touch
- [x] 7.2 Verify end to end that saving a policy, restarting the application, and
  reading the prune page again shows the saved policy still in force and reported as
  stored, and that reverting removes it and restores the configured default
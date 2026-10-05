# Tasks

## 1. Independent viewer and prune fixes

These do not depend on the scheduler and can land or revert on their own.

- [x] 1.1 Make `has_next` exact in `LogRead`/`LogLive.Index`: fetch `limit + 1`, expose the extra row separately from the display list, and derive `has_next` from its presence. Verify with a `:clickhouse`-tagged test that seeds exactly `limit` matching rows and asserts `has_next` is false, plus one seeding `limit + 1` and asserting it is true.
- [x] 1.2 Assert the extra detection row is never rendered or exported: verify a `:clickhouse`-tagged test asserts the streamed row count and the export body both equal the page size, not page size plus one.
- [x] 1.3 Drop the inert `scope` parameter from `Prune.where_clause/2` and update its caller in `Prune.run/2`. Verify the existing `Prune` tests still pass with no reference to the removed argument.
- [x] 1.4 Document the decodable-format invariant in `openspec/config.yaml` context: raw reads must resolve to `JSONCompactEachRow`, which `AshClickhouse.Connection` pins as `default_format`; the `nil`-rows branch in `LogRead.handle_result/1` is the guard for that invariant and is not dead code. Verify by re-reading the rendered context and confirming no dependency was added (`mix deps` shows no `nimble_csv`).

## 2. Hour-valued age cutoffs

- [x] 2.1 Add hour-valued entries (`1h`, `6h`, `12h`) to the `:age` family in `Filter`, ordered shortest-first alongside the existing day values. Verify `Filter.presets(:age)` returns the full ordered list and existing `Filter` tests still pass.
- [x] 2.2 Verify hour entries resolve to correct cutoffs through `Filter.resolve_preset/2` with an injected `now`. Verify a unit test asserts `{nil, now - 1h}` for `age:1h` and that the pruning bound requirement is satisfied.
- [x] 2.3 Verify the prune page now renders the widened shortcut set without a template change. Verify a LiveView test asserts the new hour shortcuts are present, driven from `Filter.presets(:age)` rather than restated.

## 3. Retention policy and its configured default

- [x] 3.1 Add the retention policy struct and config/env parsing: enabled flag, run time, and retained age, where an absent or empty value yields a disabled policy rather than raising. Verify a unit test covers present, absent, empty, and malformed values, and that no malformed value fails boot.
- [x] 3.2 Implement effective-policy resolution that returns the runtime override when present and the configured default otherwise, and reports which layer supplied it. Verify a unit test asserts override-wins, default-fallback, and that the reported source is correct in each case.
- [x] 3.3 Verify the configured default survives a restart while an override does not. Verify a test that resolves the policy with no override matches the configured value, then again after simulating an empty runtime state.

## 4. Retention scheduler

- [x] 4.1 Add the supervised scheduler process holding the override in its own state, with no ETS table and no separate state owner. Verify a test reads and writes the override through the process and asserts it is readable from another process.
- [x] 4.2 Implement next-occurrence computation from the wall clock in UTC, recomputed after each fire rather than a fixed interval sleep. Verify a unit test asserts the computed occurrence for a given `now` and run time, and that recomputation self-corrects after a clock jump.
- [x] 4.3 Make startup inert: assert no delete is dispatched on boot or when a scheduled time has passed. Verify a test starts the process with a missed occurrence and asserts no `Prune.run/2` call occurs.
- [x] 4.4 Implement the run path as a composition of the existing age-cutoff path (`presets(:age)` → `Filter.parse/1` → `Prune.run/2`) with no new SQL. Verify a `:clickhouse`-tagged test seeds rows older and newer than the cutoff and asserts only the older rows are deleted.
- [x] 4.5 Verify the run path adds no predicate construction of its own. Verify by asserting `Filter.predicates/1` and `Prune.where_clause/1` are the only sources of the delete predicate, with no second `ALTER TABLE` builder in the diff.

## 5. Supervision wiring

- [x] 5.1 Start the scheduler in `LoggerDashboard.Application` after `ClickhouseExLogger.Repo` and before the `Endpoint`, under the existing `:one_for_one` strategy. Verify the application boots and the scheduler is alive.
- [x] 5.2 Verify a repo restart does not take the scheduler down and a scheduler restart does not disturb the endpoint. Verify with a supervised test asserting the restart behaviour under `:one_for_one`.

## 6. Prune page retention controls

- [x] 6.1 Display the effective retention policy on the Prune page, identifying whether it came from the configured default or from an override that will not survive a restart. Verify a LiveView test asserts both states render differently, driven from the reported source.
- [x] 6.2 Add the edit control that stores a runtime override. Verify a LiveView test asserts the effective policy changes after the edit and that no configured value was written.
- [x] 6.3 Add the explicit confirmation step for arming, stating the resolved scope and retained age, with cancel leaving the policy unarmed. Verify a LiveView test asserts no delete is dispatched before confirmation and that cancel deletes nothing.
- [x] 6.4 Verify an already-armed policy keeps running without re-confirmation. Verify a test asserts a subsequent run dispatches with no further prompt.

## 7. Unattended run audit trail

- [x] 7.1 Log the scope acted on, the applied cutoff, and dispatch success or failure for every unattended run. Verify with `ExUnit.CaptureLog` that a dispatched run records scope and cutoff.
- [x] 7.2 Record a failed run's reason rather than reporting success. Verify a test forces a delete failure and asserts the log names the failure and no success is reported.

## 8. Verification

- [x] 8.1 Run `mix precommit` with a running ClickHouse and fix every pending issue. Verify the command exits clean.
- [x] 8.2 Confirm the `:clickhouse`-tagged suite covers the new scheduler delete, the exact `has_next` boundary, and the widened age shortcuts. Verify no new test silently relies on an undecodable format, and that the nil-rows guard still has a test.
- [x] 8.3 Verify the safety properties end to end with no configuration present. Verify the app boots, scheduled pruning is disabled, and no unattended delete can occur until a policy is configured and confirmed.
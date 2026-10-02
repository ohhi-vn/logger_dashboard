# Tasks

## 1. Filter: relative-range presets

- [x] 1.1 Add a `preset` field to `Filter` plus `@window_presets` and `@age_presets` tables in `lib/logger_dashboard/logs/filter.ex` (window: `10m`, `1h`, `6h`, `24h`, `7d` → both bounds set; age: `1d`, `3d`, `7d`, `30d`, `90d` → `from` left `nil`), and verify `Filter.t()`'s typespec includes `preset: String.t() | nil`.
- [x] 1.2 Add `Filter.resolve_preset/2` taking `(preset, now)` and returning `{:ok, {from, to}}` — `{now - duration, now}` for a window preset, `{nil, now - duration}` for an age preset, `{:ok, {nil, nil}}` for `nil`/`""`, and `{:error, message}` for an unrecognized id. Verify with `filter_test.exs` cases covering every preset id, both bounds' shapes, and an unknown id.
- [x] 1.3 Resolve `preset` inside `Filter.parse/1` against `DateTime.utc_now()`, applying the single precedence rule from design D3: when `preset` is present it determines both bounds and any explicit `from`/`to` in the same request is ignored; otherwise fall through to the existing `parse_range/1`. Verify `filter_test.exs` asserts the precedence both ways, and that the existing "from after to" and "not-a-date" rejection scenarios still pass.
- [x] 1.4 Confirm `Filter.predicates/1` is unchanged and still emits `node IN (?, ?) AND level = ? AND timestamp >= ? AND timestamp <= ? AND message LIKE ?` for a preset-resolved filter, since `parse/1` returns a struct indistinguishable from an explicitly-bounded one. Verify `mix test test/logger_dashboard/logs/filter_test.exs` passes with no edits to the existing predicate-order assertion.

## 2. Shared range-control component

- [x] 2.1 Create `LoggerDashboardWeb.RangeInputs` with a bound control that renders a UTC-labelled `from`/`to` text field (named, authoritative) beside an unnamed `type="datetime-local"` picker, both with stable DOM ids derived from an id prefix. Verify the field keeps its existing `name` (e.g. `filters[from]`, `prune[from]`) so form submits and existing test helpers are unaffected.
- [x] 2.2 Add the `.UtcDateTime` colocated JS hook that syncs the two inputs per design D2: on mount, ISO text field → `YYYY-MM-DDTHH:MM` picker value; on picker change, `YYYY-MM-DDTHH:MM` → `YYYY-MM-DDTHH:MM:SSZ` text value; on text change, ISO → picker, clearing the picker when unparseable. Verify the colocated hook compiles into the bundle and that no picker input carries a `name`, so only the text field is submitted.
- [x] 2.3 Add a shortcut button row that takes a preset family (`:window` or `:age`), renders one `phx-click` button per id in that family, and marks the active preset. Verify the buttons for `:window` and `:age` are the two distinct sets from 1.1 and that a page passing `:age` cannot render a two-bound shortcut.
- [x] 2.4 Import `LoggerDashboardWeb.RangeInputs` in the `:html_helpers` block of `lib/logger_dashboard_web.ex` so all three LiveViews can use it, and verify `mix compile --warnings-as-errors` succeeds.

## 3. Log page: filters, shortcuts, and row rendering

- [x] 3.1 Replace the `from`/`to` `<.input>` fields in `LogLive.Index` with the shared bound control and add the `:window` shortcut row plus an "All time" button, keeping `#logs-filter-form`, `#logs-list`, `#logs-pagination`, `#logs-empty`, and the active-nodes block intact. Verify `log_live_test.exs` existing DOM assertions still pass.
- [x] 3.2 Add `handle_event("preset", ...)` and `handle_event("all_time", ...)` that `push_patch` with `preset=<id>` or with `from`/`to`/`preset` dropped respectively, and update `handle_event("filter", ...)` to drop `preset` from the submitted params so a manual edit is never overwritten. Verify a `render_click` on a shortcut leaves `#logs-filter-form`'s text fields showing the resolved UTC instants.
- [x] 3.3 Add `preset` to the `Map.take` allowlist in both `handle_params/3` and `normalize_filter_params/1`, and reset `offset` to 0 when a preset or all-time action changes the range. Verify selecting a shortcut from page 2 lands on page 1 of the new window.
- [x] 3.4 Rewrite the log row per design D6 as a two-line row: a header line carrying `node`, UTC `timestamp`, and `level`, above a body line carrying `message` and the available `module`/`function`/`file`/`line`. Give the row a level-derived left accent plus a badge carrying the level as text, reusing the existing daisyUI level vocabulary so color never carries level alone.
- [x] 3.5 Render non-empty `metadata` behind a collapsed `<details>` on the row body, closing the gap where the `log-viewing` spec has always required `metadata` and the viewer never showed it. Verify with a `:clickhouse`-tagged test that a row with metadata shows it and a row without metadata renders no metadata element.
- [x] 3.6 Keep the pagination indicator's `Offset N · Limit N` wording unchanged and verify `log_live_test.exs` still finds `Offset 25 · Limit 25` at `log_live_test.exs:138`.

## 4. Prune page: picker and age shortcuts

- [x] 4.1 Replace the `from`/`to` `<.input>` fields in `PruneLive.Index` with the shared bound control and add the `:age` shortcut row. Verify `#prune-form` is still present and the `prune[from]`/`prune[to]` field names are unchanged.
- [x] 4.2 Add `handle_event("preset", ...)` that `push_patch`es the prune page's own params with `preset=<id>` and drops `from`/`to`, leaving `scope` and `node` untouched. Verify the selected scope and node value survive the click.
- [x] 4.3 Confirm the prune form's submit drops `preset` so an edited bound replaces the shortcut's cutoff, and confirm no shortcut button reaches `handle_event("preview")`, `Prune.parse/1`, or `Prune.run/1`. Verify `handle_event("confirm")` remains the only handler reaching `Prune.run/1` and that it still requires a prior successful preview.
- [x] 4.4 Verify the bounded-prune spec scenarios: a selected age shortcut satisfies `require_bounds/1`, clearing the shortcut's `to` restores the unbounded rejection, and `Prune.describe/2` states the resolved cutoff in `#prune-preview-scope`.

## 5. Analysis page: shared controls

- [x] 5.1 Replace the `from`/`to` `<.input>` fields in `AnalysisLive.Index` with the shared bound control and add the `:window` shortcut row, leaving `#analysis-filter-form` and the other Analysis DOM ids intact. Verify `analysis_live_test.exs` passes unchanged.

## 6. Shell width

- [x] 6.1 Remove `max-w-6xl` from both the header row and `<main>` in `Layouts.app` (`layouts.ex:55` and `layouts.ex:87`), keeping the `px-4 sm:px-6 lg:px-8` padding so nav and content stay aligned and content still stops at the padding edge. Verify no `max-w-*` remains on either shell container.
- [x] 6.2 Remove the page-level `max-w-3xl` from `PruneLive.Index`, so no page narrows the shell's container further. Verify the homepage, Logs, Analysis, and Prune all render their content within the same container.

## 7. Verification

- [x] 7.1 Add `time-range-input` coverage to the existing suites: preset resolution and rejection in `filter_test.exs`; shortcut click, all-time, unknown-preset rejection, and picker/text-field agreement in `log_live_test.exs`; age shortcut, bound-clearing rejection, and scope preservation in `prune_live_test.exs`.
- [x] 7.2 Add assertions for the two-line row shape — header carrying node, UTC timestamp, and level; body carrying message and source location; level present as text alongside the accent — referencing stable row DOM ids rather than text content.
- [x] 7.3 Bring up ClickHouse per the project context (`:clickhouse`-tagged tests are not excluded, so `mix precommit` fails without one) and run `mix precommit`, fixing any failure introduced by this change.

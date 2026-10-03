# Tasks

## 1. Analysis request ordering

- [x] 1.1 Add `sort_by: :value` and `sort_order: :desc` to the `AshDyan.run/2` request map in `LoggerDashboard.Logs.Analysis.level_frequency/2`; verify with a new case in `test/logger_dashboard/logs/analysis_test.exs` that the seeded rows yield `hd(result.series).data` in descending order (`error` count 2 before `info` count 1) and that the label order matches it
- [x] 1.2 Add the same two options to `node_frequency/2`; verify with a new case in `test/logger_dashboard/logs/analysis_test.exs` seeding rows on two nodes and asserting the node with more rows is the first label
- [x] 1.3 Confirm `volume_over_time/3` sends neither option and still returns chronologically sorted labels; verify with a new case in `test/logger_dashboard/logs/analysis_test.exs` seeding rows across two hours and asserting the returned labels are ascending

## 2. Analysis bucket normalization

- [x] 2.1 Make `LoggerDashboard.Logs.Analysis.normalize_bucket/1` public with a `@doc` explaining that it maps an unsupported bucket onto the default and is idempotent; verify with a new case in `test/logger_dashboard/logs/analysis_test.exs` that it returns `:hour` for an unrecognized string, `:hour` for `nil`, and `:day` for both `"day"` and `:day`
- [x] 2.2 Leave the page's offered buckets (`hour`/`day`) unchanged; verify by asserting the existing `filters_bucket` select still offers exactly those two options in the LiveView test

## 3. Result rendering

- [x] 3.1 Replace `pairs/1` in `LoggerDashboardWeb.AnalysisLive.Index` with a helper returning `{series_names, rows}`, where each row is `[label | one_value_per_series]` and a `nil` result yields `{[], []}`; verify with a new case that a single-series `%AshDyan.Result{labels: ["a"], series: [%{name: "count", data: [3]}]}` yields `{["count"], [["a", 3]]}` and a two-series result yields one row carrying both values
- [x] 3.2 Render `#analysis-levels`, `#analysis-volume`, and `#analysis-nodes` from that helper as a `<thead>` of series names over rows whose first cell is the label; give each series header `data-series={name}` and each value cell `data-series={name}`; verify by rendering the page and asserting each table has a `<thead>` and one `<tbody>` row per label
- [x] 3.3 Give each table its own label-column header (`Level`, `Bucket`, `Node`) so a single-series result does not present a count under a level's name; verify by asserting `#analysis-levels thead th[scope="row"]`-style headers exist and that `#analysis-volume` labels its first column `Bucket`

## 4. Applied-query state

- [x] 4.1 In `handle_params/3`, normalize the `bucket` param once with `Analysis.normalize_bucket/1` and merge `Atom.to_string(bucket)` into the form params built from `Filter.to_params/1`, so the select shows the bucket the query used; verify with a new LiveView case that `/analysis?bucket=day` yields `#filters_bucket option[value="day"][selected]` and that `/analysis?bucket=nope` yields `option[value="hour"][selected]`
- [x] 4.2 Pass the normalized bucket atom to `Analysis.volume_over_time/3` in `load_analysis/3`; verify with a new LiveView case that `/analysis?bucket=day` renders the day-bucketed volume table and that a submitted form carrying `bucket=day` keeps `day` after the round trip
- [x] 4.3 Add a `clear_results/1` helper and call it from the `{:error, _}` branch of `handle_params/3` so `levels`, `volume`, `nodes`, and `charts` are emptied and `filter_error` is assigned last; verify with a new LiveView case that a page which first renders seeded results, then patches to `/analysis?from=bad-date`, shows `#analysis-filter-error` and renders no `#analysis-levels tbody tr`, no `#analysis-volume tbody tr`, and no `#analysis-nodes tbody tr`
- [x] 4.4 Assign `Analysis.applied_limit(limit: limit)` instead of the bare `limit` in `load_analysis/3`, matching `mount/3`; verify with a new LiveView case that `#analysis-limit` reports the capped value after a query runs

## 5. Regression tests

- [x] 5.1 Create `test/logger_dashboard_web/live/analysis_live_data_test.exs` with `async: false` and `@moduletag :clickhouse`, seeding rows under a unique node tag via `ClickhouseExLogger.Insert.insert/1` per `test/logger_dashboard/logs/analysis_test.exs`, and scoping each page to that node; verify the file runs green against the local ClickHouse
- [x] 5.2 Add a case asserting that with rows on two levels, `#analysis-volume` renders a `data-series` value cell for **every** level the analysis produced, so dropping a series fails the test; verify by temporarily reverting the helper to the old head-of-list behavior and confirming the case fails
- [x] 5.3 Add a case asserting `#analysis-nodes` lists its rows in descending count order and that its single series name is shown; verify it fails against the unpatched request options
- [x] 5.4 Add a case asserting a scope matching no rows renders the tables with headers and zero rows rather than failing; verify against a node tag with no rows

## 6. Verification

- [x] 6.1 Run `mix precommit` with a running ClickHouse and confirm `compile --warnings-as-errors`, `deps.unlock --unused`, `mix format`, and the full suite all pass
- [x] 6.2 Run `openspec validate fix-analysis-result-presentation --strict` and confirm the delta applies cleanly onto `openspec/specs/log-analysis/spec.md` with no orphaned requirement

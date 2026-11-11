# Tasks

## 1. Filter domain support

- [x] 1.1 Add an `exclude` field to `LoggerDashboard.Logs.Filter` with parsing and `to_params/1` rendering, and verify `filter_test.exs` covers parsing and round-tripping
- [x] 1.2 Add exclude predicate emission to `Filter.predicates/1` (single and multi-term), and verify unit tests cover exclusion and combination with search

## 2. Logs page

- [x] 2.1 Add `exclude` to `@filter_keys` and render an exclude input in the filter form, and verify the control renders on `/logs`
- [x] 2.2 Carry `exclude` in the Logs-to-Analysis handoff params, and verify the link includes it

## 3. Analysis page

- [x] 3.1 Add `exclude` to `@filter_keys` and render an exclude input in the analysis filter form, and verify the control renders on `/analysis`

## 4. Prune safety

- [x] 4.1 Drop `exclude` (like `search`) in `Prune.parse/1`, and verify a prune request carrying `exclude` ignores it

## 5. Integration verification

- [x] 5.1 Run `mix precommit` and fix any failures, including ClickHouse-backed suites when a server is available

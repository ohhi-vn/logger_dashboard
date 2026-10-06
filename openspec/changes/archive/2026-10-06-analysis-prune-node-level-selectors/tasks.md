# Tasks

## 1. Analysis page click-filters

- [x] 1.1 Load distinct node options in `AnalysisLive` via the existing `list_nodes/0` (failure degrades to empty list, text input stays), and verify a LiveView test shows options independent of the current page
- [x] 1.2 Add node toggle clicks (`toggle-node`) and level clicks (`select-level`) through URL-param patch preserving range and bucket, and verify LiveView tests for add-toggle, remove-toggle, last-node-returns-to-all, and level select/replace/clear

## 2. Prune page click-selectors

- [x] 2.1 Load distinct node options in `PruneLive` via the existing `list_nodes/0` (failure degrades to empty list, text input stays), and verify a LiveView test shows the options alongside the node input
- [x] 2.2 Add node option clicks that set single-node scope (replace value, scope `node`, preserve range/level, no preview or delete triggered) and level clicks that set `level`, and verify LiveView tests for replace-semantics, confirmation-still-required, range/level preservation, and unknown-level ignored

## 3. Verification

- [x] 3.1 Extend LiveView coverage for every new scenario in `specs/log-analysis/spec.md` and `specs/log-pruning/spec.md` and verify the focused analysis/prune test files pass with a running ClickHouse
- [x] 3.2 Run `mix precommit` with ClickHouse available and verify no failures before requesting review

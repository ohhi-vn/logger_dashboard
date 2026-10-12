# Tasks

## 1. Logs filter rework (badge-only nodes, auto-apply + Refresh)

- [x] 1.1 Remove node text input and Apply/Reset from `LogLive.Index` filter card, add select-all and Refresh controls, and verify the rendered filter shows badges + select-all + Refresh with no node text field and no Apply/Reset via LiveView test
- [x] 1.2 Wire select-all/clear to whole-system scope (delete `node` param) and toggle/preset/picker/page-size to immediate `push_patch` refetch, and verify toggling a node and Refresh update rows and URL without Apply via LiveView test
- [x] 1.3 Make search and datetime text fields commit-only (change/submit with debounce, never per-keystroke, dropping `preset` on manual submit) and verify typing alone runs no query while commit refetches via LiveView test

## 2. Logs multi-expansion

- [x] 2.1 Replace `:expanded_id` + `collapse_previous/4` with an `:expanded_ids` MapSet reset on filter/page change, and verify expanding a second row keeps the first expanded via LiveView test
- [x] 2.2 Add Expand-all / Collapse-all actions over the current page rows (re-streaming only affected rows, preserving column widths, export/copy semantics) and verify expand-all shows all full messages and collapse-all returns all rows to single-line via LiveView test

## 3. Analysis filter parity

- [x] 3.1 Apply the badge-only node selector with select-all and the Refresh + auto-apply model (no node text input, no Run/Reset) to `AnalysisLive.Index`, and verify controls and immediate recompute of level/volume/node breakdowns via LiveView test
- [x] 3.2 Keep bucket control, handoff params, rejected-filter-clears-results, and search commit-only behavior intact under the new model, and verify bucket handoff plus invalid-level rejection render no stale results via LiveView test

## 4. Prune filter parity, default scope, prune-all shortcut

- [x] 4.1 Remove prune node text input, keep badge-only single-node selection with select-all, keep level badges and age shortcuts, and verify no text field is rendered and badge selection updates scope without dispatching preview/delete via LiveView test
- [x] 4.2 Default prune page state to `all-nodes` scope while keeping `Prune.parse/1` guardrails verbatim (absent scope rejected, single-node-only, time-bounded, no GET delete), and verify opening `/prune` shows whole-system selected and unbounded preview still rejected via LiveView test
- [x] 4.3 Add the prune-all shortcut (scope `all-nodes` with cleared bounds/level, state-only, clears stale preview) and Refresh state re-resolve, and verify triggering it changes scope only with no preview/confirm/delete dispatched via LiveView test
- [x] 4.4 Keep preview count + bounded newest-rows sample, confirmation copy, destructive confirm styling, and retention section unchanged under the new filter, and verify preview-then-confirm flow still deletes only the resolved scope via LiveView test

## 5. Integration verification

- [x] 5.1 Run `mix precommit` with a running ClickHouse (required for `:clickhouse`-tagged tests) and verify the full suite passes with no new warnings
- [x] 5.2 Manually verify Logs (toggle/select-all/Refresh/search commit/expand-all/collapse-all/pagination/export/copy), Analysis (parity + handoff + bucket), and Prune (default-all + prune-all + bound rejection + preview/confirm) read correctly at wide and narrow viewports with keyboard focus visible

## 6. Prune scope-select removal and All-time unbounded mark (follow-up)

- [x] 6.1 Remove the prune scope select control and the prune-all shortcut, keeping scope in the request params via badge/Select-all actions only, and verify no scope select and no prune-all button render while badge selection still sets the scope via LiveView test
- [x] 6.2 Add the timeless `All time` entry to the `:age` preset family with `{nil, nil}` resolution and identity-preserving parse, and verify the shortcut clears both bounds, keeps the scope, and dispatches no preview/delete via LiveView test
- [x] 6.3 Narrow `Prune.parse/1` so the bound check is skipped if and only if the All-time mark is present, keep the preview merge dropping the mark when the form carries an explicit bound, and verify marked-unbounded previews reach confirm while hand-cleared bounds stay rejected via LiveView test
- [x] 6.4 State the unbounded blast radius in the All-time confirmation copy and verify the confirmation names every-row-in-scope deletion via LiveView test
- [x] 6.5 Run `mix precommit` with a running ClickHouse and verify the full suite passes with no new warnings

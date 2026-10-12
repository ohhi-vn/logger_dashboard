# Design

## Context

See proposal.md (Why) for motivation and specs for the behavior contract. Current state: `LogLive.Index` holds a single `:expanded_id` (opening one row closes the previous via `collapse_previous/4`), a `filter` form with `Apply filters`/`Reset` submits, and a comma-separated `node` text input alongside `toggle-node` badges. `AnalysisLive.Index` mirrors that shape plus `bucket`. `PruneLive.Index` defaults `prune_params` to `%{"scope" => "node"}`, accepts single-node text input plus `select-node` badges, and gates deletes behind `Prune.parse/1` (explicit scope, single-node-only, time-bounded, no GET delete). Shared range UI lives in `RangeInputs` (`bound/1`, `shortcuts/1`); predicates stay in `Filter.predicates/1` with bound params. No data-layer or DDL change is needed.

## Goals / Non-Goals

**Goals:**
- One badge-only node selector shared by all three pages, with whole-system as the empty scope (NULL-node rows included).
- Auto-fetch filter model on Logs/Analysis without losing bookmarkable URLs; prune keeps its explicit preview/confirm gate.
- Multi-open expansion with page-scoped expand-all/collapse-all that preserves column widths and export/copy semantics.

**Non-Goals:**
- No change to predicate SQL, bound-param discipline, raw-format handling (`LogRead.handle_result/1`), pagination sizes, retention scheduler, or auth.
- No new JS chart/filter framework; reuse existing `push_patch` + `handle_params` round-trip and colocated hooks.
- No relaxation of prune guardrails (explicit scope, single-node-only, time-bounded, no GET delete).

## Decisions

- **URL params stay the source of truth; auto-fetch is `push_patch`, not polling.** Every badge/preset/bucket/page-size control already patches the URL and re-runs through `handle_params`. The redesign deletes the `Apply`/`Reset` submits and relies on those handlers, adding a `Refresh` event that re-invokes the current load path (`load_logs`/`load_total`, `load_analysis`, prune state re-resolve) with the existing `filter_params`/`prune_params` and unchanged URL. Alternative (form `phx-change` live-filtering without URL) rejected: it would break bookmarks, back-button, and the Logs-to-analysis handoff, all of which read the URL.
- **Search and datetime text fields commit, never per-keystroke.** Buttons patch immediately; the `search`/`from`/`to` inputs commit on change/submit (with `phx-debounce` on change) into the same `push_patch(drop preset)` path used today. This bounds ClickHouse QPS while keeping one validator (`Filter.parse/1`). Per-keystroke fetch rejected as a load risk.
- **`Select all` means whole-system (delete the `node` param), not enumerating options.** Enumerating all known nodes into `node=a,b,c` would exclude NULL-node rows and future nodes and would bloat URLs. Clearing to the empty scope preserves the spec's whole-system semantics (includes NULL) and reuses the existing `clear_nodes` path; the new button is discoverability placed in the options row, with identical behavior. It is hidden/disabled when scope is already whole-system or when no options exist.
- **Expansion becomes a `MapSet` of DOM ids (`:expanded_ids`), default empty.** `toggle-expand` adds/removes one id and re-inserts only that streamed row; `expand-all` fills the set with all current page `row_dom_id`s and re-streams the page; `collapse-all` clears it. `collapse_previous/4` and `:expanded_id` are removed. Column widths are CSS variables on `#logs-table` and untouched by re-streaming. Export (`format_page`) and copy read `page_rows`, independent of expansion. Filter/page change resets the set (rows are new). Single-open behavior is intentionally not preserved.
- **Prune default becomes `all-nodes` in page state only; `Prune.parse/1` still rejects absent scope.** Change `mount`/`handle_params` defaults from `"node"` to `"all"` so the page opens whole-system, but keep the `scope == ""` rejection and single-node/multi-node checks verbatim. There is no scope selector control: node badges set `scope=node` with the node value, Select all sets `scope=all`, and the scope so chosen travels in the request params exactly as the removed selector sent it — `Prune.parse/1` is untouched. The `prune-all` shortcut is deleted.
- **Prune text input removed; single-node selection is badge-only.** `select-node` already replaces the value and clears stale previews through `handle_params`; the `<.input node>` is deleted. Multi-node paste is therefore unrepresentable in the UI, and `Prune.parse/1`'s multi-node rejection stays as the backstop for hand-crafted URLs.
- **`All time` is an explicit unbounded mark, not missing bounds.** It is a timeless entry in the `:age` preset family resolving to `{nil, nil}` whose identity survives parsing (unlike age shortcuts, whose `preset` is dropped at preview so an edited cutoff wins). `Prune.parse/1` skips the bound check if and only if that mark is present; bounds cleared by hand carry no mark and stay rejected. The preview merge keeps the mark only when the submitted form carries no explicit bound — typing a `from`/`to` after All time drops the mark and yields a bounded prune, exactly as manual edits replace age shortcuts today. The confirmation for a marked scope must state that every row in scope will be deleted.

## Risks / Trade-offs

- [Auto-fetch raises query volume] → Mitigation: buttons patch discretely (one query per click, same as today); only text inputs are debounced/committed; Refresh is manual. No polling or per-keystroke reads.
- [Stale expansion after Refresh] → Mitigation: Refresh and any filter/page patch reset `:expanded_ids`; expand-all applies to the rows actually on screen, never across pages.
- [`All time` is a deliberate unbounded delete] → Mitigation: only the explicit mark permits it — hand-cleared bounds stay rejected, typing a bound drops the mark, and preview/confirm still gate every delete with the full blast radius stated. No other override is added.
- [Bookmark compatibility] → Mitigation: `node`, `level`, `from/to`, `preset`, `limit/offset`, `bucket` param names and `Filter.parse/1` semantics are unchanged; only the removed text-input and Apply/Reset controls disappear. Old URLs with `node=a,b` still parse (badges reflect them); nothing reinterprets stored params.
- [Empty-node table] → Mitigation: options row shows the existing "no known nodes" copy; select-all/clear hidden or disabled; scope stays whole-system so the pages remain usable.

## Migration Plan

- Deploy as a single UI change; no migration, no config, no backfill. Rollback is a revert of the three LiveViews (no persisted state to unwind).
- Verify with `mix precommit` (needs running ClickHouse for `:clickhouse`-tagged tests) plus manual passes: Logs toggle/refresh/expand-all, Analysis parity, Prune default-all + all-time unbounded confirm + bound-rejection paths.

## Open Questions

- None. The prune-all-vs-bounded interaction is resolved above (shortcut selects scope only; bound still required). If reviewers want a true one-click unbounded whole-system delete, that needs a separate spec change to the time-bounded guardrail, not part of this change.

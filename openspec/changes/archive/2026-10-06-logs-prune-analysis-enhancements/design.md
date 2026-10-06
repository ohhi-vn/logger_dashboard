# Design

## Context

See `proposal.md` for motivation. Current state shaping the approach:

- `LogRead.list_logs/2` builds `WHERE` from `Filter.predicates/1` with bound params, fetches `limit + 1` rows newest-first to derive `has_next` without a count. `LogLive.Index` shows `Offset/Limit` only.
- `Prune.parse/1` folds scope into a `Filter` (whole-system carries empty nodes, `search` forced to `""`), `where_clause/1` delegates to `Filter.predicates/1`, and preview today renders only `Prune.describe/2` text before `Prune.run/2` issues `ALTER TABLE … DELETE`.
- `Analysis` runs three AshDyan queries (`level_frequency`, `volume_over_time`, `node_frequency`) via `dyan_filters/1`, which deliberately drops `search` because Ash 3.33 exposes no `:like` operator — a `message` predicate fails with `NoSuchFunction` before the data layer. Analysis page has no search input and no handoff from Logs.
- Project invariants (see `openspec/config.yaml`): all raw SQL through `ClickhouseExLogger.Repo.query/3` with bound params only; projection order derived from `LogView` attributes; `nil` rows treated as error; relies on the data layer's `JSONCompactEachRow` pin.

## Goals / Non-Goals

**Goals:**

- One shared predicate source for page, total, export, prune preview/delete, and keyword analysis.
- Preview-before-delete that an operator can trust (same filter object into count, sample, and delete).
- Zero-retype Logs → Analysis flow, with keyword semantics identical on both pages.

**Non-Goals:**

- No DDL, retention-policy, scheduled-prune, or export-scope changes.
- No prune-by-message: manual prune stays node/range/level only; `search` is not added to `Prune.parse/1`.
- No relevance ranking, highlighting, or full-text index work; keyword stays `LIKE` with viewer wildcard translation.
- No new bucket granularities on Analysis.

## Decisions

### 1. Total via `SELECT COUNT(*)` on the same `Filter.predicates/1`

Add `LogRead.count_logs/1` issuing `SELECT COUNT(*) FROM <table> WHERE <same where>` with the same bound params as `list_logs/2`. `LogLive.Index` loads page + total together; rejected filters and failed reads show no total (never stale); `has_next` keeps its `limit + 1` derivation so total and paging cannot disagree about the filter set.

- Alternative: `SELECT count() OVER ()` window or Ash aggregate — rejected. The window couples counting to the page query's `LIMIT` and Ash cannot push the `message LIKE` predicate at all.
- Alternative: infer total from paging — rejected. That is exactly the inference bug the `limit + 1` probe fixed.

### 2. Prune preview = count + bounded newest-rows sample from the parsed filter

Add `Prune.preview_counts/1`-style reads (exact helper name at implementation): `COUNT(*)` plus `SELECT <LogRead projection> … ORDER BY timestamp DESC LIMIT <small fixed N, e.g. 10>` using `where_clause/1` on the `Filter` returned by `Prune.parse/1`. Both reuse bound params; sample rows decode through the same normalize path as viewer rows. `PruneLive.Index` clears `preview/preview_filter/preview_scope` on any `handle_params` change (existing behavior) and on `cancel`; `confirm` still runs only from stored `preview_filter/scope`.

- Alternative: `EXPLAIN`-based estimate — rejected. Estimates understate blast radius; the spec requires the count the delete will execute.
- Sample size stays fixed and small (single-digit): large enough to catch a wrong scope, small enough that preview never becomes a second viewer page.

### 3. Handoff as a plain `/analysis` link built from the parsed filter

`LogLive.Index` builds `~p"/analysis?#{params}"` from `Filter.to_params(filter)` plus the page's `bucket` default, mapping `node/search/from/to/level` one-to-one. Analysis treats handoff params identically to typed ones (same `Filter.parse/1` path, same validation, same rejected-clears-results). No session/clipboard state.

- Alternative: POST or LiveView message passing — rejected. A GET link is bookmarkable, back-button safe, and matches the existing filter-in-URL convention on both pages.

### 4. Keyword analysis via raw-SQL aggregations mirroring the three AshDyan queries

When `filter.search` is empty, keep the existing AshDyan path untouched. When non-empty, run three raw aggregates through the same `WHERE` (including `message LIKE ?` from `Filter.to_like_pattern/1`):

- level mix: `SELECT level, COUNT(*) … GROUP BY level ORDER BY COUNT(*) DESC LIMIT ?`;
- volume: `SELECT <bucket-trunc(timestamp)>, level?, COUNT(*) … GROUP BY … ORDER BY bucket ASC LIMIT ?`;
- per-node: `SELECT node, COUNT(*) … GROUP BY node ORDER BY COUNT(*) DESC LIMIT ?`, rolling NULL/`''` to `unknown` as today.

Results are shaped back into the `%AshDyan.Result{}` labels/series form the template and charts already render, so ordering, empty-scope tables, bound disclosure, and rejected-clears-results behavior are unchanged. All values bound; `nil` rows → error; bucket truncation uses ClickHouse date functions consistent with current `minute/hour/day` buckets.

- Alternative: pass `message` through AshDyan `filters` — rejected per project context: Ash 3.33 rejects `:like` before the data layer, and `LogView`'s `allow_filters_on([…, :message])` does not make it reachable.
- Alternative: separate keyword service/table — rejected. Same-table `LIKE` keeps one source of truth and no migration.

## Risks / Trade-offs

- [Extra reads per render] Logs page and prune preview each add 1–2 bounded queries → Mitigation: `COUNT(*)` is cheap in ClickHouse; sample capped at single digits; analysis bound (`max 10_000`) already caps keyword aggregations.
- [Leading-`%` `LIKE` scans] `*timeout*` cannot use skip indexes → Mitigation: same cost the viewer already pays; analysis discloses its row bound so slow scopes read as bounded, not exact.
- [Preview/delete skew] Rows arriving between preview and confirm shift the count → Mitigation: confirmation text states the count was taken at preview time; confirm reuses the same validated filter rather than a frozen row list, matching current async-delete semantics.
- [`nil`-rows misread as empty] New raw aggregates inherit the driver's silent `nil` on undecodable formats → Mitigation: reuse `LogRead.handle_result/1` semantics — `nil` rows is an error, never zero.

## Migration Plan

Additive reads + UI only; no config, DDL, or backfill. Rollback is a revert of the change. Deploy order is irrelevant (no cross-node contract).

## Open Questions

- None that change specs, approach, or task breakdown. Final sample size (5 vs 10) and total placement in the pagination bar are template details settled at implementation.

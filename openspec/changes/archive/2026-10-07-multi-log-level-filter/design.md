# Design

## Context

See proposal.md Why for motivation. Current state: `LoggerDashboard.Logs.Filter` owns a single `level: String.t()` (`"all"` = no predicate), validated against `@levels`, emitted as `level = ?` in `predicates/1`. `Analysis.dyan_filters/1` maps `"all"` to omitted and any other value to equality. Both `LogLive.Index` and `AnalysisLive.Index` expose the same pattern: clickable badges issuing a `select-level` event that overwrites the `level` URL param, plus a single-select in the filter form. Node scope already solved the analogous problem with comma-separated `node` param + toggle handler. Raw SQL reads bind every value; AshDyan level filtering relies on Ash `in`/equality pushdown (unlike `message`, which must stay raw SQL).

## Goals / Non-Goals

**Goals:**

- One level-scope representation shared by Logs, Analysis, handoff, and bookmarks.
- OR semantics with bound parameters on both the raw-SQL path and the AshDyan path.

**Non-Goals:**

- Prune page UI stays single-select (it inherits multi support from the shared filter without a UI change).
- No change to level vocabulary (`error/warning/info/debug`), row rendering, or export format.
- No new query knobs (no AND semantics, no exclusion lists).

## Decisions

### 1. Comma-separated `level` param, parsed to a level set

Keep the param name `level` and accept `error,warning` exactly like `node`. Rationale: reuses the established multi-value URL convention, keeps bookmarking/back-button behavior, and makes Logs-to-Analysis handoff a string passthrough. Alternative (repeated `level=error&level=error`) was rejected: Phoenix/LiveView patch param handling and `Filter.to_params/1` round-trip are string-oriented, and two conventions for the same idea would drift.

`Filter` normalizes `nil`/`""`/`"all"` (case-insensitive, whitespace-tolerant) to `[]`, splits on comma, trims, downcases, dedupes, and rejects the whole filter on any unknown entry. It also accepts a list value (multi-select form submits a list) and joins it before the same pipeline, so string and list inputs converge.

### 2. `level IN (...)` for any non-empty set, omitted when empty

`predicates/1` emits `level IN (?, ...)` with one bound placeholder per level; empty set emits nothing. Rationale: one clause shape covers 1..N levels, mirrors `maybe_push_nodes`, and keeps "no level text reaches the SQL string". Alternative (keep `=` for single) was rejected: two shapes for the same predicate doubles test surface for no behavioral gain.

### 3. AshDyan filter uses `%{in: levels}` uniformly

`maybe_put_level` maps `[]` to omitted and any non-empty list to `%{level: %{in: levels}}`, following the proven `maybe_put_nodes` shape (`:in` is exposed by `Ash.Query.Operator` and built as `IN` by AshClickhouse). Rationale: one representation for pushdown, and keyword-filtered raw-SQL aggregations reuse `Filter.predicates/1` so both analysis paths agree. Alternative (equality for single, `in` for multi) rejected for the same reason as decision 2.

### 4. Toggle badges + multi-select form, both through the `level` param

Badges change from overwrite to toggle: read the active set from URL params (so toggling works while a validation error is shown), add/remove the clicked level, write back comma-joined or drop the param when empty. `all` badge clears to empty. The form `<select>` becomes multi-select bound to the same param; submit path reuses `Filter.parse/1` as the single validator. Rationale: matches the node-options interaction operators already know, and keeps validation/bookmarking unified instead of splitting badge state from form state.

## Risks / Trade-offs

- [Risk] Form multi-select may submit `level` as a list, a single string, or absent depending on selection → Mitigation: `Filter.parse_level(s)` normalizes all three shapes; LiveView `normalize_filter_params` preserves list values.
- [Risk] AshDyan `%{in: [single]}` behaves differently from equality on some backends → Mitigation: cover single- and multi-level analysis with `:clickhouse`-tagged tests; fall back to equality-for-single if the driver diverges (spec scenarios are unchanged either way).
- [Risk] Existing tests assert replace-on-click level behavior → Mitigation: update those assertions to toggle semantics as part of the change; new scenarios in the deltas are the acceptance set.
- [Risk] Shared `Filter` change touches prune reads → Mitigation: single-level prune submissions parse to a one-element set and emit `IN (?)`, semantically identical to `= ?`; no prune UI change, covered by existing prune tests.

## Migration Plan

No DDL, no config, no dependency change. Deploy as a normal release. Rollback by reverting; old single-level URLs (`?level=error`, `?level=all`, absent) parse identically before and after. New multi-level URLs on an old build fail validation on the unknown comma value rather than silently widening scope.

## Open Questions

None. Backward-compatible param shape and toggle semantics are fixed by the spec deltas above.

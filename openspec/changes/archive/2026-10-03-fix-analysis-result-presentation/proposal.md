# Proposal

## Why

The analysis page reports numbers that are not the numbers it computed. Five
defects were found by reading the page against `AshDyan`'s actual result shape
and by rendering its form controls; every one of them is a case where the page
states something the server did not do. The most serious is silent data loss in
the volume table, which drops every level but one while presenting the remainder
as the whole.

These are user-visible correctness bugs on the page an operator uses to decide
whether a system is healthy, so they are worth fixing before the page gains
more features.

## What Changes

All five are in the analysis surface (`log-analysis`). No dependency changes, no
DDL, no public API change.

1. **Volume-over-time table drops every series but the first.** `volume_over_time/3`
   is called with `split_by_level: true`, so `AshDyan` pivots the result into one
   series per level. `pairs/1` takes `[%{data: data} | _]` — the head of the list
   only — so the table renders one level's counts against the full set of bucket
   labels, with no column naming the level. The chart beside it draws every
   series, so chart and table disagree. The table becomes a label × series grid
   that shows all series and names each one.

2. **The bucket select never shows the bucket in effect.** `handle_params/3`
   builds the form from `Filter.to_params/1`, which has no `"bucket"` key, so
   `@form[:bucket]` is `nil`. `Phoenix.HTML.Form.options_for_select/2` emits no
   `selected` attribute for a `nil` value (verified), so the browser falls back
   to displaying the first option — `hour` — while `handle_params/3` ran the
   query with `bucket=day`. Submitting the form then re-sends `hour` and
   silently discards the operator's choice. The form now carries the normalized
   bucket that was actually applied.

3. **Rejected filters leave the previous results on screen.** The `{:error, _}`
   branch of `handle_params/3` assigns `filter_error` and the form but never
   touches `@levels`, `@volume`, `@nodes`, or `@charts`, so a request that never
   ran a query still shows the last request's numbers beside the error. The
   error path clears them, as the log viewer already does.

4. **Per-node counts are ordered alphabetically, not by count.** `log-analysis`
   requires a node table "ordered descending" so hot nodes are visible.
   `AshDyan.Engine.Formatter.frequency/2` sorts labels with `Enum.sort/1`
   because no `sort_by` is requested, so the table reads `a@h`, `b@h`, `c@h`
   regardless of volume. `level_frequency/2` and `node_frequency/2` now pass
   `sort_by: :value`, which `AshDyan` supports for `:frequency`, so the node
   with the most rows is first.

5. **The disclosed limit is not the applied limit.** `mount/3` discloses
   `Analysis.applied_limit(limit: 1_000)` but `load_analysis/3` overwrites it
   with the bare `1_000`. They agree only while `max_limit` exceeds 1000. The
   post-query path discloses the capped value, the same helper `mount/3` uses.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `log-analysis`. Two requirements gain normative text; one is added:
  - *Volume over time* gains the requirement that a split result renders a
    value for every series and names each one.
  - *Level frequency breakdown* gains the requirement that the breakdown is
    ordered descending by count.
  - A new requirement covers the page showing the query it actually ran: the
    bucket control reflecting the applied bucket, and a rejected filter leaving
    no results rendered.

Two of the five defects are **conformance fixes against requirements that
already exist**, so they produce no delta:

- Defect 4 violates *Per-node breakdown*, which already requires a node table
  "ordered descending" so hot nodes are visible.
- Defect 5 violates *Bounded analysis with limit disclosure*, whose scenario
  already requires the page to display "the applied limit alongside the charts".

## Impact

- `lib/logger_dashboard_web/live/analysis_live/index.ex` — all five fixes. The
  only behavioral surface that changes is what the page renders and the order
  of rows within a table.
- `lib/logger_dashboard/logs/analysis.ex` — `level_frequency/2` and
  `node_frequency/2` pass `sort_by: :value`. `volume_over_time/3` is unchanged:
  `:time_bucket` rejects `:sort_by` (bucket labels must stay chronological).
- `openspec/specs/log-analysis/spec.md` — one requirement added, two modified.
- No route, endpoint, dependency, or ClickHouse DDL change. No schema change.
- `mix precommit` must pass, including the full suite against a running
  ClickHouse.

### Observed but out of scope

- `LoggerDashboard.Logs.Prune.qualified_table/0` derives the table name from
  `Repo.config()[:database]` while `LogRead.table/0` derives it from
  `AshClickhouse.DataLayer.qualified_table/1`. They resolve to the same table
  today, and the prune path interpolates a config value without the
  `AshClickhouse.Identifier.validate_database!/1` check the dependency itself
  applies. Worth a separate change; it does not affect analysis.
- `LogLive.Index` renders `aria-controls="false"` on a row whose panel is
  closed, because `false && "id"` reaches a non-boolean attribute. Cosmetic
  accessibility wart in a different capability.
- `Analysis.buckets/0` and `Analysis.default_bucket/0` are public and called
  only from inside `Analysis`. The page hard-codes its two offered buckets, which
  is a deliberate product choice, so there is no drift to fix today.

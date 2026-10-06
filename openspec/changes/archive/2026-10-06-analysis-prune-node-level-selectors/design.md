# Design

## Context

See `proposal.md` (Why) and `specs/log-analysis/spec.md`, `specs/log-pruning/spec.md` for requirements. Current state: `AnalysisLive.Index` filters by URL params (`node` comma-list, `level` select, `bucket`) parsed through `Filter`, with `clear_nodes` preserving range/level; `PruneLive.Index` drives a `scope` (`node`/`all`) + single `node` text input + `level` select through `Prune.parse/1`, which rejects multi-node values and requires confirmation before `Prune.run/1`. The logs page already ships clickable node toggles, clickable levels, and `LogRead.list_nodes/0` plus `Filter.levels/0` as the single vocabularies.

Constraints from project context apply: raw SQL with bound parameters only, no DDL, `handle_result/1` nil-rows branch stays.

## Goals / Non-Goals

**Goals:**
- Same click-to-filter feel on all three pages, backed by the same node source and level vocabulary.
- Prune clicks that can never widen or execute a delete by themselves.

**Non-Goals:**
- Multi-node prune, saved node sets, or changes to confirmation, retention, charts, or buckets.
- Copy/columns work (logs-page only, already shipped).

## Decisions

### 1. Reuse `list_nodes/0` and `levels/0` verbatim on both pages

Both pages load `@node_options` via the existing `LogRead.list_nodes/0` (failure → `[]`, text input remains) and render levels from `Filter.levels/0`. No new query, no second vocabulary.

Alternatives considered: per-page option queries scoped by current filters (rejected — options must be page-independent per spec, and one bounded query is cheaper than three).

### 2. Analysis clicks mirror the logs page exactly

`toggle-node` adds/removes the value in the `node` param; `select-level` sets the `level` param; both `push_patch` preserving range/bucket. Same toggle helper shape as `LogLive.Index`, adapted to analysis param keys (which include `bucket` instead of `limit`/`offset`).

### 3. Prune node click replaces and scopes, never deletes

A prune node click writes `scope=node` plus the single node value into `prune_params` and patches — it selects, then stops. The existing `preview` → `confirm` flow and `Prune.parse/1` single-node rejection stay the only path to `Prune.run/1`, so a click cannot execute or widen a delete; it can only narrow the pending scope to one node. Level click sets `level` the same way.

Alternatives considered: toggling multi-nodes on prune then rejecting at parse (rejected — offers-then-rejects is worse than single-select; the single-node rule is a safety invariant, not a UI limitation).

## Risks / Trade-offs

- [Click that looks like it prunes] → Click only fills the form state; the confirmation panel still gates every delete, and its text names the resolved scope.
- [Stale node options] → Options are discovery, not validation: a typed name outside the bound still works, and options reload per navigation like the logs page.
- [Prune click while scope is `all`] → Click overrides to `node` scope explicitly; it never deletes under `all` since confirmation is still required.

## Migration Plan

No DDL, no config, no backfill. Deploy as a normal release; rollback is a plain revert — URL params keep their existing shapes on both pages.

## Open Questions

- None.

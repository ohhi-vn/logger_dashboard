# Proposal

## Why

Operators investigating incidents need to see `error + warning` together while excluding noisy `info/debug` rows. Both Logs and Analysis currently accept a single `level` value, forcing repeated single-level queries or falling back to `all` with noise.

## What Changes

- Replace the single-value `level` filter on Logs page and Analysis page with a multi-select supporting zero, one, or more of `error`, `warning`, `info`, `debug`.
- Empty selection (or `all`) applies no level predicate; one or more selected levels match rows whose `level` equals any selected value (OR semantics).
- Clickable level badges toggle in/out without disturbing node, search, range, bucket, or pagination state; form select becomes multi-select with the same semantics.
- Shared `LoggerDashboard.Logs.Filter` parses/validates/emits the multi-level predicate with bound parameters; Logs-to-Analysis handoff carries the multi-level scope identically to hand-entered values.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `log-viewing`: Level filter changes from single-select (`level=error | ... | all`) to multi-select (zero or more levels, OR match, empty = no predicate).
- `log-analysis`: Analysis scope level filter changes identically; all breakdowns (level frequency, volume, per-node) aggregate over the multi-level scope.

## Impact

- Affected code: `LoggerDashboard.Logs.Filter` (parse, `to_params`, `predicates`), `LoggerDashboard.Logs.Analysis.dyan_filters/1`, `LogLive.Index` + `AnalysisLive.Index` (`select-level` handler, form params, handoff), both filter templates.
- No DDL change; `logs` table stays upstream. No new dependencies.
- Compatibility: single-level URLs (`?level=error`) and `level=all`/absent keep working as one-element / empty scopes; multi-level URLs use comma-separated `level=error,warning` matching the existing `node` convention.

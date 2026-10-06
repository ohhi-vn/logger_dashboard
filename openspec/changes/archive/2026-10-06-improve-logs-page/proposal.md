# Proposal

## Why

Filtering logs today requires typing exact `node@host` names and level values by hand, and copying a row's full context requires manual assembly. Operators cannot discover available nodes, cannot toggle filters by clicking, and cannot resize or expand the table for wide messages.

## What Changes

- Nodes filter: fetch distinct node values from ClickHouse and render them as clickable options; clicking toggles the node in/out of the active scope (empty selection = all nodes, NULL included).
- Level filter: render `all`, `error`, `warning`, `info`, `debug` as clickable options; clicking selects that level (single-select, `all` clears the predicate).
- Row copy: add a per-row action that copies the full record — UTC timestamp, level, node, untruncated message, and source location when present — in the same field order and escaping as the existing page export.
- Messages table: add explicit columns (timestamp, level, node, message, source location) with a resizable layout and keep the existing single-row expand/collapse for full message plus metadata.

## Capabilities

### New Capabilities

- None — all behavior extends the existing viewer.

### Modified Capabilities

- `log-viewing`: node selector becomes a clickable distinct-node list; level selector becomes clickable; rows gain copy-full-info; table gains columns plus expandable/resizable behavior.

## Impact

- `LoggerDashboardWeb.LogLive.Index` template and events (node/level click toggles, per-row copy payload via `push_event` + clipboard hook in `app.js`).
- `LoggerDashboard.Logs.LogRead` / `Filter` read path: new distinct-nodes query with bound parameters; no DDL change (table stays upstream).
- `LoggerDashboard.Logs.LogLine`: reuse field order/escaping for copy text.
- Tests: LiveView interaction tests for click-toggles, copy payload, column/resize/expand behavior.

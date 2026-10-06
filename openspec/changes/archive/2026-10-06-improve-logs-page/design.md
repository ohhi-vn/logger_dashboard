# Design

## Context

See `proposal.md` (Why) and `specs/log-viewing/spec.md` for requirements. Current state: `LoggerDashboardWeb.LogLive.Index` drives all filtering through URL params (`node` comma-list, `level` select, `limit`/`offset`) parsed by `Filter`, read by `LogRead.list_logs` raw SQL, rendered as a streamed flex-line list with single-row expand and a `logs-download` window event for export. Node names are hand-typed; there is no distinct-node listing, no click-toggles, no per-row copy, and no column/resize structure.

Constraints from project context apply: text predicates stay raw SQL; every value is a bound parameter; projection derives from the resource; `handle_result/1` nil-rows branch stays; no new decoders or DDL.

## Goals / Non-Goals

**Goals:**
- Clickable node/level filtering that round-trips through the existing URL-param filter model.
- A distinct-node source that stays consistent with the active table without a second store.
- Per-row copy that reuses export field order/escaping.
- Explicit resizable columns that compose with streams + single-row expand.

**Non-Goals:**
- Multi-select levels, saved views, or column-visibility configuration.
- Server-side persistence of column widths or copy history.
- Any change to pagination, search, time-range, prune, or analysis behavior.

## Decisions

### 1. Distinct nodes via a bounded raw `SELECT DISTINCT` in the existing read path

Add a `list_nodes`-style read alongside `list_logs` that issues `SELECT DISTINCT node ... WHERE node IS NOT NULL AND node != '' ORDER BY node ASC LIMIT ?` through `ClickhouseExLogger.Repo.query/3`, decoded through the same `handle_result` shape (nil rows = error, never empty).

Rationale: keeps the sanctioned raw-SQL escape hatch, needs no DDL or Ash operator, and reuses the bound-parameter and error-visibility invariants. Alternatives considered: Ash distinct aggregation (rejected — no pushdown story and a second query model) and deriving options from the current page (rejected — spec requires options independent of the page).

Bound the result (e.g. a few hundred) and order server-side so scanning is stable; the comma text input stays as the fallback for nodes outside the bound or not yet observed.

### 2. Click-toggles as URL-param patches, not local assigns

Node click toggles the value in/out of the `node` param (parse → toggle → `nodes_to_param`); level click sets the `level` param. Both go through `push_patch` like the existing `clear_nodes`/`filter` events, so `Filter.parse/1` remains the single validator and back/forward/bookmark behavior is unchanged.

Alternatives considered: client-only toggling with a follow-up query (rejected — splits filter truth between client and URL and breaks export/page consistency).

### 3. Copy as a `push_event` + clipboard window listener reusing `LogLine.format/1`

The row's copy button pushes the preformatted line (timestamp, level, node-or-placeholder, untruncated message, location when present) built by `LogLine.format/1`, and `app.js` writes `detail.body` via `navigator.clipboard.writeText`, mirroring the existing `phx:logs-download` Blob flow. No new route; failure surfaces as a flash rather than a silent no-op.

Alternatives considered: a colocated per-row hook reading DOM text (rejected — DOM holds the shortened message, so copy would disagree with export) and server-side clipboard (impossible — clipboard lives on the client).

### 4. Columns as a real table/grid with client-side resize handles

Replace the flex-line row with an explicit column layout (`timestamp`, `level`, `node`, `message`, `location`, actions) where `message` is the flexible truncated column. Resize handles adjust widths in the browser only (a small colocated hook or `app.js` listener); widths are never sent to the server, never enter the URL, and never trigger a re-query. Expand/collapse keeps the current `stream_insert`-at-index mechanism so the panel and toggle state stay consistent.

Alternatives considered: persisting widths in URL/assigns (rejected — layout is not filter state and would pollute links) and CSS-only `resize` on cells (rejected — inconsistent across browsers inside streamed rows).

## Risks / Trade-offs

- [Distinct scan cost on a large `logs` table] → Bound with `LIMIT`, select only `node`, no joins; load once per filter change, not per row. Accept that a very large fleet may truncate the option list — the text input remains the escape hatch.
- [Clipboard requires secure context / permission] → Copy is a user gesture; on denial show a flash and keep the expanded panel (which holds the same text) as the manual fallback.
- [Resize + streams interaction] → Widths live outside LiveView-rendered attributes (CSS variables/inline styles managed by the hook) so re-inserted rows inherit them without a server round trip.
- [NULL/empty nodes] → Options exclude NULL/empty; the all-nodes scope still includes them per the existing requirement.

## Migration Plan

No DDL, no config, no backfill. Deploy as a normal release; rollback is a plain revert — URL params (`node`, `level`) keep their existing shapes, so old links work before and after.

## Open Questions

- None. Column-width persistence and multi-level select were explicitly excluded; if requested later they need new specs.

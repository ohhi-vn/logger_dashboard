# Design

## Context

See proposal.md Why for motivation. Current state: five pages (Home, Logs, Analysis, Prune, Login) share `Layouts.app` shell and daisyUI light/dark themes, but each page styles its own headers, filter cards, badges, tables, and buttons inline with Tailwind utilities. Shared `core_components.ex` (button/input/table) exists but pages bypass it in places (custom badge buttons, ad-hoc table markup like Analysis `result_table` and the prune preview). Custom raw CSS is limited to the log viewer's `.logs-grid` column layout in `app.css`, which uses the required Tailwind v4 import syntax. A light/dark/system theme toggle already exists in the shell.

## Goals / Non-Goals

**Goals:**

- One visual language for repeated elements, owned in shared components so it cannot re-drift.
- Readable density that respects the pinned one-line-row invariant.

**Non-Goals:**

- No layout restructuring, no new theme/fonts/dark mode, no Chart.js chart recoloring (charts keep their current rendering; only their surrounding cards/tables are unified).
- No behavior, routing, param, event, or DOM-id changes.

## Decisions

### 1. Drive repeated elements through shared components, not per-page utilities

Headers, filter cards, tables, buttons, badges, flash/error blocks converge on `core_components.ex` (`button`/`input`/`table`), `Layouts.app`, and one filter-card pattern reused by Logs/Analysis/Prune. Rationale: shared components are the only single source that keeps five pages consistent over time. Alternative (page-by-page utility-class tweaks) was rejected: it produces the same drift again the next time a page is touched.

### 2. Theme through daisyUI tokens, never hardcoded colors

All color changes use semantic tokens (`base-*`, `primary`, `error`, …) so light and dark themes move together; contrast is then a token property, not a per-page property. Rationale: hardcoded colors break the untouched theme and the existing theme toggle. Alternative (per-theme overrides in raw CSS) was rejected: it duplicates every rule and rots.

### 3. Raw CSS only for what utilities cannot express

New raw CSS is limited to cases like the existing `.logs-grid` (shared column layout with resize variables). Everything else stays Tailwind utilities; no `@apply`, and the `app.css` Tailwind v4 import syntax is preserved. Rationale: project convention keeps the stylesheet small and the utility scan the source of truth for classes.

### 4. Visible focus via shared components using `:focus-visible`

Focus rings land in the shared button/input/badge/table-action styles once, so every page inherits them, including the theme-toggle and sign-out controls. No control removes the outline without replacing it. Rationale: one place guarantees the "always visible focus" requirement instead of auditing five templates. Alternative (per-template focus classes) was rejected for the same drift reason as decision 1.

### 5. Density inside existing invariants

Tighter rows/tables keep the one-line row, truncation-with-ellipsis, resizable-column, and bounded-preview-sample contracts untouched; spacing tightens padding/gaps, never the row-height or table-content rules the specs pin. Rationale: density is the ask, but those invariants are load-bearing readability behavior with regression tests.

## Risks / Trade-offs

- [Risk] Existing tests assert presentational markup (classes, selected options) → Mitigation: keep all DOM ids, event names, params, and routes stable; update only assertions that pin styling, never behavior assertions.
- [Risk] A token combo passes AA in light theme but fails in dark (or vice versa) → Mitigation: check both themes when touching any color pair; the tasks include a two-theme contrast check.
- [Risk] Unifying tables tempts unifying the Analysis `result_table` and prune preview sample into one component, widening the diff → Mitigation: share styling via the same classes/component API, but do not merge components with different data shapes; styling convergence is the goal, not component consolidation.
- [Risk] "Consistent" can creep into restructuring filter layouts → Mitigation: restyle in place per the agreed latitude; any move/merge of controls is out of scope and stops at proposal review.

## Migration Plan

No backend, DDL, config, or dependency change. Deploy as a normal release; rollback by reverting. Cached CSS busts via the existing asset fingerprint pipeline.

## Open Questions

None. Styling latitude (restyle in place) and the spec deltas fix the approach and task breakdown.

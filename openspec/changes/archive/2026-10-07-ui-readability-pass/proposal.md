# Proposal

## Why

Operators read this dashboard for long stretches during incidents, but the pages grew independently: inconsistent spacing, type, and control styling across Logs/Analysis/Prune/Home/Login, loose data density, and weak focus/contrast cues make scanning slower and harder than it should be.

## What Changes

- Restyle in place (no layout restructuring, no new theme/fonts, no dark mode): unify type scale, spacing rhythm, and control styling across Home, Logs, Analysis, Prune, and Login using the existing Tailwind/app.css bundle.
- Tighten data density where scanning matters (log rows, analysis tables, prune preview) while keeping rows legible and one-line truncation/expansion intact.
- Make interactive elements consistently identifiable and keyboard-navigable: visible focus states, preserved aria/pressed/current cues, level conveyed by text as well as color.
- Fix inconsistencies between pages (headers, filter cards, buttons, badges, tables, empty/error states) so the same element looks and behaves the same everywhere.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `dashboard-shell`: shared frame/nav/content container — consistent header, nav, flash, and container styling plus keyboard/focus treatment.
- `log-viewing`: log list and filter presentation — readable row density, consistent badge/filter/table/empty-state styling, preserved truncation and level-as-text.
- `log-analysis`: cards, charts-adjacent tables, and filter presentation — consistent with Logs, legible table density.
- `log-pruning`: form, confirmation preview, and outcome presentation — consistent with the other pages, destructive actions unmistakable.
- `dashboard-auth`: token page presentation — same input/button/error language as the dashboard forms.

## Impact

- Affected code: HEEx templates (`LogLive`, `AnalysisLive`, `PruneLive`, home, login, `Layouts.app`, `core_components.ex`) and `app.css` (Tailwind v4 import syntax preserved, no `@apply`, no new bundles).
- No backend, query, filter-semantics, routing, or auth-logic changes; no new dependencies; no DDL.
- Compatibility: all URLs, params, LiveView events, and DOM ids used by tests stay stable unless a test asserts purely presentational markup (those assertions get updated, not the behavior).

# Design

## Context

See proposal.md for motivation. Current state (observed in `LogLive.Index` and `AnalysisLive.Index` templates):

- Both pages render level toggle badges **above** the filter card **and** a `multiple` level `<select>` **inside** the filter card — two level controls for one filter.
- Logs filter card is `md:grid-cols-6` with children spanning 2+1+1+1+1+1 = 7 units, so the last cell wraps unpredictably; the tall multi-select is the box that overlaps its neighbours.
- Analysis filter card is `md:grid-cols-6` with a first row of 2+2+1+1 = 6 (clean) but a second row of level (1) + bucket (1) + actions (`md:col-span-6`) = 8 units, so the second row overflows.
- Filter behaviour itself is sound and well-tested: `Filter.parse_levels/1` accepts comma-string or list, `select-level` toggles through the `level` URL param, unknown values reject, values are bound parameters. No query or parsing change is needed.

Constraints: Phoenix 1.8 HEEx + Tailwind v4 grid already in use; shell shared visual language (filter card, badges, focus indicators) must be kept; no new deps, no inline `<script>`, no migration (DDL is upstream).

## Goals / Non-Goals

**Goals:**
- Exactly one level control per page, non-overlapping at all viewports, inside the filter card.
- Grid spans that sum correctly per row on `md+` and stack cleanly below `md`.
- Zero change to filter semantics, URL shape, validation, or query path.

**Non-Goals:**
- No change to level vocabulary, node options, search syntax, datetime handling, pagination, charts, export, auth, or retention.
- No new shared component extraction unless the two cards can share without indirection (prefer duplication of a few grid classes over a premature abstraction).
- No visual redesign beyond fixing overlap (no new theme, no daisyUI, no custom CSS framework).

## Decisions

### 1. Keep toggle badges, remove the in-form multi-select

- **What:** Delete the `<.input field={@form[:level]} type="select" multiple ...>` from both filter forms. Keep the existing badge groups (`#logs-level-options`, `#analysis-level-options`, including an `all` reset badge) and move each group inside its filter card as a full-width (`md:col-span-6`) row with a visible label.
- **Why:** Badges already implement the full spec (toggle without disturbing others, `all` reset, `aria-pressed`, keyboard operable, works while a validation error is shown, handoff-compatible). The multi-select is the redundant copy that creates the overlap and the grid overflow; removing it resolves both at once and removes code (`form_params` level-as-list mapping, `join_level_param` list-join branch become reducible).
- **Alternatives considered:**
  - *Keep multi-select, remove badges:* rejected — badges are the spec-mandated clickable toggles, match the node-options pattern operators already learn once, and are covered by toggle scenarios; a multi-select alone would need re-specifying and is harder to use on touch/keyboard.
  - *Keep both and only fix grid spans:* rejected — fixes overlap but keeps two controls bound to one filter, which disagree visually (badge active vs. select highlighted) and double the test surface.

### 2. Give each filter card explicit rows that sum to 6

- **What (Logs):** Row 1: node (`md:col-span-2`), search (`md:col-span-2`), from (1), to (1) = 6. Row 2: level badge group (`md:col-span-6`). Row 3: per-page select (1–2 cols) + Apply/Reset + shortcuts row (`md:col-span-6` actions bar, level removed from it). Row widths below `md` are single-column stack (existing `grid-cols-1`).
- **What (Analysis):** Row 1: same as Logs (node 2 + search 2 + from 1 + to 1 = 6). Row 2: level badge group (`md:col-span-6`). Row 3: bucket select (1–2 cols) + Apply/Reset + shortcuts actions bar. The current `md:col-span-6` actions div stays full-width but no longer shares its row with level/bucket inputs.
- **Why:** Makes overlap structurally impossible: every row sums to ≤ 6, the tall control (badges wrap via `flex-wrap`) owns a full row so wrapping grows the row instead of covering neighbours.
- **Alternatives considered:** *Custom CSS / absolute positioning fix:* rejected — the bug is grid-span arithmetic plus a duplicated tall control; Tailwind grid rows already express the fix with no new CSS.

### 3. Keep the URL and parse path untouched; simplify form helpers only where they become dead

- **What:** `Filter.parse_levels/1`, `levels_to_param/1`, `level_active?/2`, and the `select-level` toggle handlers stay as-is (still the single validator and single writer through the `level` param). `form_params/1` drops the `"level" => filter.levels` list mapping once no select consumes it; `join_level_param/1` / `allowed_filters/1` list-join branches can be removed only if no other form field submits a list, otherwise left harmless for backward-compatible bookmarked URLs.
- **Why:** Smallest blast radius — presentation-only change with no query, validation, or bookmark breakage. Keeping the parser list-tolerant costs nothing and preserves old links.
- **Alternatives considered:** *Rewriting filter params or event flow:* rejected — no behavioural gain, larger regression surface.

## Risks / Trade-offs

- [Risk] Existing LiveView tests assert on the multi-select (`#logs-filter-form select`, `level` form field options) → Mitigation: update assertions to the single badge group (`#logs-level-options`, `#analysis-level-options` inside the form); toggle scenarios already cover behaviour.
- [Risk] Full-width level row pushes Apply/Reset one row lower → Mitigation: acceptable and intended; filter card grows vertically instead of overlapping — matches how node badges already wrap.
- [Risk] Narrow-screen stacking could still feel long → Mitigation: single-column stack is the existing mobile pattern for the whole card; no horizontal overlap is the requirement, not card height.

## Migration Plan

- Template + minor helper cleanup in the two LiveView modules; no config, migration, or deploy steps. Rollback is a revert of those files.
- Verify with `mix precommit` (needs running ClickHouse for `:clickhouse`-tagged tests per project context) plus manual check at 375px, 768px, and 1280px widths: level row on its own row, no overlap, toggles still patch the `level` param.

## Open Questions

- None. Badge labels, order (`Filter.levels/0`), and `all`-reset semantics are already specified; grid spans are fixed above.

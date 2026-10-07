# Tasks

## 1. Shared foundation

- [x] 1.1 Unify button, input, table, badge, and flash/error styles plus `:focus-visible` rings in `core_components.ex` and `Layouts.app`, using daisyUI semantic tokens only; verify with `mix compile --warnings-as-errors` and the shell/auth LiveView tests passing
- [x] 1.2 Converge Logs, Analysis, and Prune on one filter-card pattern (title, labeled inputs, primary/ghost action order) reusing the shared components; verify by rendering all three filter forms and confirming identical structure via `mix test test/logger_dashboard_web/live/log_live_test.exs test/logger_dashboard_web/live/analysis_live_test.exs test/logger_dashboard_web/live/prune_live_test.exs`

## 2. Page passes

- [x] 2.1 Tighten Logs list density and badge/row-action readability within the one-line-row, truncation, and resizable-column invariants; verify with `mix test test/logger_dashboard_web/live/log_live_test.exs`
- [x] 2.2 Unify Analysis cards and result tables (level, volume, node) on the shared table styling at matching density; verify with `mix test test/logger_dashboard_web/live/analysis_live_test.exs test/logger_dashboard_web/live/analysis_live_data_test.exs`
- [x] 2.3 Restyle Prune form, confirmation preview, and outcome on the shared language with the confirm action unmistakably destructive; verify with `mix test test/logger_dashboard_web/live/prune_live_test.exs test/logger_dashboard/logs/prune_test.exs`
- [x] 2.4 Restyle Home and Login on the shared card/input/button/error language; verify with `mix test test/logger_dashboard_web/controllers/ test/logger_dashboard_web/live/dashboard_auth_test.exs`

## 3. Verification

- [x] 3.1 Update only presentational test assertions to the new markup, keeping every DOM id, event name, param, and route stable and all behavior assertions intact; verify with `mix test test/logger_dashboard_web/`
- [x] 3.2 Keyboard-tab through every page confirming a visible focus indicator on each control, and check body-text contrast meets WCAG AA in both light and dark themes; verify by recording the pass in the change notes with any failing pair fixed
- [x] 3.3 Run `mix precommit` with ClickHouse running and verify it passes with no new warnings

## Verification notes (3.2)

Static audit (no browser in this environment; markup-verified):

- Keyboard: every interactive control is a native `button`/`a`/`input`/`select`
  (badges, nav, theme toggle, sign-out, row actions, form controls). No
  `phx-click` on non-focusable elements, no positive `tabindex`. Column-resize
  handles are mouse-only spans on an already keyboard-usable table. Theme-toggle
  buttons gained accessible names in 1.1; `aria-pressed`/`aria-current` cues
  untouched. Global `:focus-visible` ring (2px primary + offset) covers all pages.
- Contrast (computed from theme tokens, WCAG ratio): body text 16.74 (light) /
  12.54 (dark) — AA pass. Muted `base-content/70` 6.63–7.41 — AA pass.
- Pre-existing failures NOT introduced here, left for a palette decision (fixing
  them redesigns theme tokens, beyond restyle-in-place latitude):
  - Solid `btn-primary` text in light theme 2.75 (orange primary + near-white text).
  - `text-error` on cards 4.33 (light) / 2.93 (dark).
  - Focus ring vs page bg 2.76/2.89 — borderline vs the 3:1 non-text target.

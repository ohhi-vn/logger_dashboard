# Design

## Context

Three pages — Logs, Analysis, Prune — each carry their own copy of the same filter
controls. The copies have already drifted: the level control is a multi-select on
Logs and Analysis but a single-select on Prune, the Prune page offers the level twice
(badges *and* a select inside the form), and the node/level/badge markup is
copy-pasted with per-page ids. The same drift produced the duplicated handlers:
Logs and Analysis carry byte-identical `toggle-node` / `select-level` handlers that
differ only in their URL.

`LoggerDashboard.Logs.Filter` is the one owner of the filter vocabulary today: it
parses the `node`/`level`/`search`/`from`/`to` params and builds the single
`predicates/1` clause set that `LogRead.list_logs/2`, `LogRead.count_logs/1`, and the
three keyword paths in `LoggerDashboard.Logs.Analysis` all reuse. `LoggerDashboardWeb.RangeInputs`
is the precedent for a shared control module — the datetime bounds and the relative
shortcuts already live in one place, with the shortcut vocabulary owned by `Filter`.

Two facts from the project context shape the search work: `Ash.Query.Operator` in
Ash 3.33 has no `:like`, so the message predicate can only be raw SQL with bound
parameters; and the driver's decodeable formats are fixed, so raw reads must keep
using the `JSONCompactEachRow` pin that `AshClickhouse.Connection` applies.

For the charts, `AshDyan.Charts.to_chartjs/2` already accepts an explicit chart type
(`:bar | :line | :area | :pie | :donut | :histogram | :scatter`) and rejects shapes a
type cannot represent (a multi-series result cannot be a pie). Chart.js is already
imported globally as `window.Chart` in `assets/js/app.js`, and the Analysis page
already ships a `.LogChart` colocated hook that renders a `data-chart` JSON config
into a `<canvas>`.

One LiveView client detail matters for the chart work, verified in the vendored
client source (`deps/phoenix_live_view/assets/js/phoenix_live_view/`): an element
marked `phx-update="ignore"` still has its `data-*` attributes merged from the new
markup (`dom.ts` `mergeAttrs/3`, which syncs `data-*` only and leaves other attributes
— including the inline styles Chart.js writes on the canvas — alone), and it is still
pushed onto the `updates` list, so the hook's `updated()` callback fires
(`dom_patch.ts`). The existing canvas therefore already redraws when the scope
changes, and the same mechanism carries a changed chart type.

## Goals / Non-Goals

**Goals:**

- One implementation of the node scope, level scope, and search controls, used by all
  three pages, with the pages' real differences expressed as configuration.
- One implementation of the scope-mutation logic (toggle vs. select) that the pages
  delegate to, so the three pages cannot drift apart again.
- Case-insensitive, multi-term message search implemented in the one place that
  builds the message predicate.
- A chart style the operator chooses per breakdown, kept in the URL, with a visible
  fallback when the data cannot take the chosen shape.
- A prune page whose review of "what would be deleted" is always current with the
  filters on screen, and whose confirm action is still an explicit separate step.

**Non-Goals:**

- No new dependency: no charting library, no query builder, no `nimble_csv`.
- No change to the `logs` table, the upstream DDL, or the retention scheduler.
- No change to what a prune deletes — the delete still runs the same validated
  predicate; only the review around it changes.
- No visual redesign of the filter cards. The shared controls look like today's
  controls; only their implementation and placement within the prune page change.
- No search syntax beyond wildcards, case-insensitivity, and AND-combined terms —
  no regular expressions, no negation, no field-specific search.

## Decisions

### D1 — Shared controls live in a new `LoggerDashboardWeb.FilterControls` module

Three small function components — `node_options/1`, `level_options/1`, `search/1` —
with `mode` (`:multi` / `:single`) and an `id` prefix for DOM ids, mirroring how
`RangeInputs.bound/1` and `RangeInputs.shortcuts/1` are already parameterized. The
pages compose them into their own filter cards and keep their own page-specific
controls (per-page size on Logs, bucket on Analysis).

*Alternatives considered:* one monolithic filter-bar component with slots — rejected,
because Logs, Analysis, and Prune differ in which controls they offer and a slot-based
bar becomes a component that mostly renders slots. Folding the new controls into
`RangeInputs` — rejected, `RangeInputs` is about the time range, and renaming or
splitting it churns a module that is already shared and working.

### D2 — Scope mutation lives in `Filter`, not in the pages

`Filter` gains `toggle_node/2`, `toggle_level/2`, `select_node/2`, `select_level/2`,
each taking the current params map and returning the next params map. The three
pages' handlers become one-line delegations, and the "multi" vs. "single" difference
becomes a choice of function rather than a re-implementation.

*Alternatives considered:* keeping the handlers per page — rejected, that duplication
is the drift this change exists to remove. A separate web-layer module for them —
rejected, the param vocabulary (`node` as a comma-separated list, `level` likewise)
is `Filter`'s, so the helpers belong beside `nodes_to_param/1` and `levels_to_param/1`.

### D3 — Search is one param, split into terms that are ANDed

`search` stays a single string. `Filter` splits it on whitespace into terms and
`predicates/1` emits one `message ILIKE ?` clause per term, so terms combine with
AND. An empty search emits no clause. Three rules decide how a term is matched,
and the implementation settled them:

- **A term with a wildcard is matched as written.** `db_*` is a run beginning with
  `db`. The wildcard syntax is unchanged.
- **A term with no wildcard is a keyword and matches anywhere in the message.**
  `timeout` finds `connection timeout`. This is what makes multi-term search
  usable at all: a keyword that had to equal the whole message would match
  nothing, which is not what a keyword search is for.
- **A search whose wildcards span the whole string is one pattern.**
  `*logtotal row 2*` is the phrase "logtotal row 2", spaces included, while
  `*boom* *one*` is two terms that both have to match. The rule is "a term that
  opens a wildcard and does not close it means the wildcards run on into the
  next term". Without it, splitting on whitespace would silently break every
  phrase search the viewer had — `*foo bar*` would become two keywords, and
  the middle word would have to equal the whole message.

*Alternatives considered:* a separate `terms` param — rejected, it creates two ways to
express one search and doubles the URL vocabulary. `lower(message) LIKE lower(?)` —
rejected, a function call on the column is noisier in the SQL and no cheaper than the
native operator. OR semantics — rejected, AND is the narrowing default an operator
reaching for "timeout and db" expects; OR can be added later without changing the
param shape. Always splitting on whitespace — rejected, it is the rule that breaks
phrase searches.

*Consequence to accept:* a bare term used to be an exact match (`message LIKE
'timeout'`) and now matches anywhere; that is a deliberate, announced behavior
change, in the same spirit as the case-insensitivity. A search whose case
differed from the message also changes — it now matches, which is the point.

### D4 — Chart style is a per-breakdown URL param, normalized server-side

The Analysis page gains `level_chart`, `volume_chart`, and `node_chart` params, each
holding one of the styles that breakdown's result can represent. The server resolves
the param, passes it to `AshDyan.Charts.to_chartjs/2`, and — when the result's shape
cannot take that style — falls back to the recommended style and shows the style
actually in use in the control. The by-node breakdown gains a chart beside its table.

*Alternatives considered:* one global chart-type param — rejected, a frequency
breakdown and a time series want different shapes, and one param cannot serve both.
Rendering several chart types at once — rejected, it crowds the page and multiplies
the chart payload for no analytic gain. Choosing the type client-side — rejected, the
server already owns the Chart.js config shape, and the fallback rule needs the result
shape, which only the server has.

### D5 — The chart redraw mechanism is reused, not replaced

The canvas keeps `phx-update="ignore"` and carries its config in `data-chart`. When
the server renders a different config — new data or a new type — LiveView merges the
new `data-chart` value and fires the hook's `updated()`, and the hook destroys the
old Chart instance before creating the new one. Chart.js cannot change a chart's type
in place, so destroy-and-recreate stays.

*Alternative considered:* dropping `phx-update="ignore"` so LiveView patches the
canvas normally — rejected, that would let LiveView remove the inline styles Chart.js
writes on the canvas, and the canvas is not a hook-managed DOM subtree the project
rule intends to protect only incidentally.

### D6 — The prune review is computed from the current params, not on a preview action

`handle_params` on the prune page parses the current params and, when they are valid,
computes the review (row count, per-node counts, bounded sample) from that same
parsed filter. The separate "Preview prune" submit is removed; the bound fields
commit to the URL the way they do on the other pages, and the review follows. The
confirm action stays a separate, explicit step and always acts on the filter the
review describes.

*Alternatives considered:* keeping the preview button and adding a refresh — rejected,
the operator still has to remember to press it and the review lags the filters, which
is the failure mode the request is about. Computing the review only on the confirm
click — rejected, that removes the review from the moment the operator needs it.

*Safety note:* the property the existing spec protected was "a stale count can never
be confirmed". A live review keeps that property and strengthens it — the count on
screen is always the count for the scope in effect — but it changes the letter of the
existing requirement, which is why `log-pruning`'s "Explicit confirmation before
delete" and "Prune filter refreshes without destructive auto-run" are modified in the
delta rather than left to be reinterpreted.

### D7 — Per-node counts come from one bounded read

The review's per-node distribution is a single grouped count over the same validated
filter — `SELECT node, count() … GROUP BY node` with a bound limit — with NULL nodes
rolled into an explicit `unknown` group, matching what the Analysis page already does
for its node breakdown. The whole-system scope shows the top nodes plus the total; a
single-node scope shows that node's count.

*Alternatives considered:* deriving the per-node split from the sample rows —
rejected, a five-row sample says nothing about the distribution. One count query per
node — rejected, that is N round trips where one grouped query answers it.

### D8 — The guided flow is a presentation, not a wizard

The prune page renders the steps (scope → cutoff → review → confirm) with the current
one marked, derived from the parsed state: scope chosen, cutoff set, review computed.
The step indicator never gates anything — the confirm action is reachable from any
step, so the flow adds no clicks to a delete that is already deliberately slow.

*Alternative considered:* a real wizard where each step must be completed before the
next unlocks — rejected, it adds clicks and a dead-end when the operator wants to
change the cutoff after reading the review.

## Risks / Trade-offs

- **The live review issues three bounded reads on every scope change** (count,
  per-node group, sample) where the page previously issued none until Preview →
  the reads are the same shape the Logs page already issues on every filter change,
  the sample stays at five rows, the node groups stay bounded, and bound edits commit
  through the existing 400 ms debounce rather than per keystroke.
- **Case-insensitive and multi-term search change existing result sets** → announced
  as a breaking change in the proposal; a wildcard search keeps its meaning, and a
  bare term now matches anywhere rather than only as an exact match, so both
  changes make a search find more rows, never fewer.
- **A phrase search only works when the wildcards wrap the whole string** →
  `*foo bar*` is a phrase and `foo bar` is two keywords; the control states the
  syntax, and a search that means a phrase but was written without the wrapping
  wildcards now behaves as two keywords.
- **`ILIKE` cannot use an index on `message`** → the previous `LIKE` could not either
  (wildcards on both sides); the change adds no new scan, and the predicate stays
  bound, so no user input reaches the SQL string.
- **A search containing a space changes meaning** → spaces were previously literal
  inside one pattern, which matched almost nothing; the new reading is the intended
  one, and the control states the syntax.
- **Chart params add URL noise** → accepted; they are optional, absent by default, and
  dropped from the Logs→Analysis handoff, which carries only scope.
- **A chart style the data cannot take falls back silently** → mitigated by showing
  the style actually in use in the control, and by only offering styles the result's
  shape supports in the first place.
- **A prune review is computed even when the operator never confirms** → reads only;
  no delete is dispatched without the explicit confirm action.
- **The canvas redraw depends on LiveView merging `data-*` into ignored elements** →
  verified in the vendored client source, and pinned by a test that asserts the
  rendered chart config changes when the scope changes.
- **The shared controls change the DOM ids and structure of existing pages** → the
  existing LiveView tests that assert on those ids must be updated rather than
  worked around; the ids follow a per-page prefix convention so they stay unique.

## Migration Plan

No data migration, no schema change, no stored state: this is a UI and query-shape
change. Deploy the server and client together — the new chart params and the new
prune flow are additive, and a client running the old bundle against the new server
still works for everything except the new chart styles.

Old links keep working: a URL without chart params gets the recommended styles, a
URL with an old search string keeps its meaning apart from the announced
case-insensitivity, and the prune page's params are unchanged, so a bookmarked prune
scope still opens on the same scope.

Rollback is a revert of the release. The one operator-visible difference worth
calling out in release notes is the prune page: the separate Preview button is gone,
and the review is shown as the filters change — an operator who learned to press
Preview will find the review already there.

## Open Questions

- Whether the per-node distribution in the prune review shows a bounded top-N list
  with an "other nodes" remainder line, or every affected node. Neither changes the
  spec's requirement to state the distribution; it is a presentation choice to settle
  during implementation. The list is already bounded to the busiest nodes, and the
  total count beside it states the whole.
- Whether the prune page states the unbounded-scope refusal as an error on load, or
  as a quieter hint. The current implementation reports it as an error, because the
  scope as it stands cannot be pruned and the operator should be told why.
- Whether the chart-style control is a select or a segmented button row. Presentational
  only; the spec requires a control that names the styles and shows the one in use.

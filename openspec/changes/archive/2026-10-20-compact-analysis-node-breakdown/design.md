# Design

## Context

See proposal.md for the motivation. The facts that shape the approach:

**The Analysis page renders three breakdowns in two separate blocks.** In
`lib/logger_dashboard_web/live/analysis_live/index.ex`, "By level" and "Volume
over time" sit in a `md:grid-cols-2` container; "By node" is a sibling
`<div>` below them that spans the full page width. All three render through
one private `result_table/1` component, which already forces them to share
their table markup — the layout is the only thing that treats them
differently.

**The chart is created by a colocated hook, and its config travels in an
attribute.** The template renders `<canvas id="analysis-chart-..." data-chart={...}
phx-hook=".LogChart" phx-update="ignore" />`. The hook reads
`this.el.dataset.chart` and calls `new window.Chart(this.el, cfg)`. The
`phx-update="ignore"` is what keeps LiveView from replacing the canvas
out from under the chart instance.

**LiveView still synchronises `data-*` attributes on an ignored element.**
`DOM.mergeAttrs/3` in `phoenix_live_view/assets/js/phoenix_live_view/dom.ts`
copies attributes whose name starts with `data-` even when the element is
ignored, and `dom_patch.ts` pushes the ignored element onto the `updates` list
so the hook's `updated()` callback still fires. `data-chart` is a `data-*`
attribute, so the config is refreshed on every re-render and the hook rebuilds
the chart. This is the mechanism the existing "the chart config is re-rendered
when the scope changes" test already exercises.

**Chart.js derives its height from its width.** `AshDyan.Charts.to_chartjs/2`
emits `options: %{"responsive" => true, "plugins" => ...}` and no
`maintainAspectRatio`, so Chart.js keeps its default (`true`) and sizes the
canvas from the container's width via the aspect ratio. The canvas is
therefore as tall as its column is wide — which is why the full-width By node
card draws an enormous chart, and why narrowing the card alone would not be
enough.

**The shell's table styling is daisyUI's, and it already has a compact step
and a pinned-header modifier.** `.table-xs` is the smallest table density and
`.table-pin-rows` pins the header row with a `base-100` background. The prune
page already renders its sample rows at `table-xs`, so the compact step is
part of this codebase's vocabulary rather than a new invention.

**The node options come from the table, the node scope comes from the URL.**
`FilterControls.node_options/1` renders the `options` it is handed — on the
Analysis page that is `LogRead.list_nodes/0`, the distinct node values in the
`logs` table, capped at 200 — and marks the ones in `selected` with
`aria-pressed` and a filled badge. The `selected` set comes from the `node`
URL param, so it can name a node the table no longer has.

**The Analysis page's node scope is currently stated twice.** `#analysis-active-nodes`
lists the active nodes as badges, and the node options right below it mark the
same nodes as pressed.

## Goals / Non-Goals

**Goals:**

- The By node breakdown stops being a full-width band and becomes a column of
  the breakdown grid, sized so the three cards read as peers.
- The page's height is set by the layout rather than by how many nodes or
  buckets happen to be in scope.
- The three breakdowns keep rendering through one shared table component, one
  shared chart mechanism and one shared control, so they cannot drift apart
  the way the current layout lets them.
- The node scope is stated in exactly one place, and that place can always
  remove what it states.

**Non-Goals:**

- No change to what any breakdown reports. Same scope, same numbers.
- No change to the Logs or Prune pages' layout, content or behaviour. The
  shared node-scope control changes underneath them (see Decision 5), and that
  is the only way they are affected.
- No virtualisation, no windowing and no server-side pagination of the result
  tables. A thousand rows still travel to the browser; they simply stop
  stretching the page.
- No change to the chart library, the chart types, the style vocabulary or the
  URL params that select a style.
- The Logs page's own active-node summary row is left alone. It is redundant
  under the new control behaviour, but removing it is a `log-viewing` change
  with its own review, and this change is scoped to the Analysis page.

## Decisions

### 1. One grid, twelve columns, three cards

The two sibling layout blocks become one `grid-cols-1 md:grid-cols-6
xl:grid-cols-12` container holding the three cards in the order By level, By
node, Volume over time.

| viewport | by level | by node | volume over time |
| --- | --- | --- | --- |
| narrow | 6 of 6 (own row) | 6 of 6 (own row) | 6 of 6 (own row) |
| `md` | 3 of 6 | 3 of 6 | 6 of 6 |
| `xl` | 3 of 12 | 3 of 12 | 6 of 12 |

**Why twelve columns at the widest breakpoint rather than three equal
fractions.** A plain `xl:grid-cols-3` would make the By node card a third of
the page and the Volume over time card a third as well, but the time-series
chart is the one that benefits from width (a week of hourly buckets has 168
x-labels) and the by-node table is the one that does not (a node name and a
count fit in a narrow column). Splitting the wide row 3/3/6 gives the time
series twice the width of either frequency breakdown, which is where the
readability actually is, and leaves By node at a quarter of the page — the
"smaller" the request asks for.

**Why grid placement follows DOM order.** The three cards are reordered in the
template so that the `md` layout falls out of their order with no `order-*`
classes. Grid placement and DOM order agree, so tab order and reading order
match what is on screen.

**Alternative considered: keep two blocks and only narrow the By node one.**
Rejected. It leaves the By node card visually detached from the other two and
preserves the exact drift the previous change set out to remove.

### 2. The chart gets a definite height

`chart_for/2` merges `"maintainAspectRatio" => false` into the options map
that `AshDyan.Charts.to_chartjs/2` returns, and each canvas moves into a
fixed-height wrapper:

```heex
<div class="relative h-56">
  <canvas id="analysis-chart-node" class="block h-full w-full" data-chart={...} phx-hook=".LogChart" phx-update="ignore" />
</div>
```

`maintainAspectRatio: false` with `responsive: true` makes Chart.js size the
canvas to its container's box instead of deriving a height from the width, and
the wrapper's `h-56` is what gives that box a definite height. The canvas
carries `block` because a canvas is inline by default and `h-full` does not
apply to an inline box.

**Why not `aspectRatio`.** Setting a fixed aspect ratio would still make the
height a function of the width — a wide column would still draw a taller
chart. The requirement is that the height does not follow the column width,
and only a definite-height container delivers that.

**Why the wrapper, rather than a height on the canvas itself.** Chart.js
measures the canvas's *parent* to decide how big to be. A height on the canvas
alone leaves the parent free to be whatever the grid gives it, and the chart
would size to the parent, not to the canvas.

**Why the option is merged in the LiveView, not in `AshDyan.Charts`.** The
option is a property of *this page's* layout — a fixed-height frame. The
dependency builds a chart config from a result; it has no opinion about how
the page frames it. Merging it in `chart_for/2` keeps the dependency
untouched and keeps the decision in the one place that knows about the frame.

**Note on `phx-update="ignore"`.** The canvas is ignored, so LiveView does not
re-apply its `class`. The class is static, so the first render's is the only
one that is ever needed. `data-chart` is a `data-*` attribute and is still
merged, so the config — and now the `maintainAspectRatio` option with it —
refreshes on every re-render, and the hook's `updated()` rebuilds the chart in
the fixed-height frame.

**Alternative considered: leave the charts responsive and let the narrower
column shrink them.** Rejected. A pie or donut would still be as tall as the
column is wide, and the three cards would not line up.

### 3. One bounded, compact, pinned result table

`result_table/1` — already shared by all three breakdowns — becomes:

```heex
<div class="max-h-64 overflow-auto">
  <table class="table table-xs table-pin-rows" id={@id}>
    ...
  </table>
</div>
```

`table-xs` is the compact step; `table-pin-rows` pins the header row with an
opaque `base-100` background so it stays readable over scrolling rows. The
`max-h-64` wrapper is what bounds the region.

**Why the bound lives in the shared component.** The three breakdowns already
share one `result_table/1`; putting the bound there gives all three the same
treatment for free, and the previous change set out to make that the rule.
A per-breakdown bound would immediately re-introduce the drift.

**Why `max-h-64` for the by-level table too, when it has at most a handful of
rows.** Because the treatment has to be uniform to be a rule. The wrapper is a
maximum, not a fixed height: the by-level table renders at its natural height
and never scrolls.

**Why not a `top-N` cap on the by-node rows.** A cap would change what a
breakdown reports, and the request is explicitly about presentation. The
scroll region gets the page back the space without touching the numbers. The
trade-off is that the browser still receives every row — see Risks.

**Alternative considered: a fixed-height region with the table's own scroll
only on the by-node breakdown.** Rejected: it makes the by-node table's
treatment different from the other two, which is the drift this project keeps
fighting.

### 4. Chart-style labels

`Analysis.chart_style_label/1` maps each style the module already offers to a
readable name — `bar` → `Bar`, `donut` → `Donut`, and so on. The chart-style
control renders that label in the button face.

**Why the label map lives in `Analysis`.** That module already owns the style
vocabulary (`@chart_styles`, `chart_styles/1`, `default_chart_style/1`). A
label map sitting next to the vocabulary cannot fall out of step with it —
adding a style without a label is a compile-visible omission rather than a
silent blank button.

**Why the id and the `phx-value-style` keep the machine name.** The style
travels in the URL as `level_chart=pie`. If the visible label were the
identifier, changing the wording of a label would change a bookmarked link.
Keeping `pie` in the URL and `Pie` on the button means the URL is stable and
the button is readable, and the existing control ids
(`analysis-chart-level-style-pie`) stay valid, so the existing tests that
address the control by id keep working.

### 5. The node scope is offered by the control, not by a second list

`FilterControls.node_options/1` renders the union of the `options` it is
handed and the `selected` set, with the active scope first and the remaining
known options after it, deduplicated.

```elixir
nodes = Enum.uniq(@selected ++ @options)
```

The control's "No known nodes." empty text is keyed on `@options == []` today.
It has to key on the rendered union instead: a scope node the table no longer
holds is rendered even when the known list is empty, and the control must not
say it has no nodes while showing one.

**Why the scope goes first.** A scope node that is not among the known
options would otherwise be appended after up to 200 known nodes, where nobody
would find it. The scope is the answer to "what am I looking at?", so it
belongs where the eye lands. This is the reason the Analysis page's separate
summary row can go: the control now carries the scope itself, in the place
the operator is already looking.

**Why the union is in the shared component rather than in the Analysis
LiveView.** `log-filter-controls` exists to keep the three pages on one
vocabulary, and a page that renders a different option set than its siblings
breaks exactly that. Applying the union once, in the component every page
uses, keeps the three pages identical and gives the Logs and Prune pages the
same guarantee for free.

**What it costs the other two pages.** The Logs and Prune pages show the
active scope at the front of their node options rather than in the middle of
the list. That is a visible change to two pages this change is otherwise not
about, and it is the reason `log-viewing`'s "Distinct node options"
requirement is modified rather than left to drift.

**Why the Analysis page's `#analysis-active-nodes` row goes.** Once the
control offers the scope, the row states the same fact in a second place. Two
statements of one fact can disagree; one cannot. The row's removal is a
`log-analysis` change because the Analysis page is where the row lives.

**Alternative considered: keep the row and leave the control alone.**
Rejected. It keeps the redundancy, and it keeps the failure mode where a scope
node the table no longer has is visible in the summary but un-clickable in the
options.

### 6. The filter card's rows

The card is `md:grid-cols-6` today, filled as: search (4) + from (1) + to (1)
= 6, then level options (6) = 6, then bucket (2) with **4 columns empty**,
then the actions (6) = 6. The Bucket select is the odd one out.

The bucket control moves up into the first row, and the first row's spans
become search (3) + from (1) + to (1) + bucket (1) = 6. The level options
keep their own full-width row, and the actions keep the last row. Every row
is now filled.

**Why the bucket belongs with the range inputs.** It is a time-dimension
control — hour or day — and it reads next to the from/to bounds. Today it
sits alone under the level row, separated from the controls it qualifies.

**Why the search gives up a column.** The search's help text is the longest
block in the card, and the search input itself is a single line. A third of
the card is still a wide input, and the help text simply wraps one line
earlier. The from and to bounds keep the width they have today.

**Why not leave the half-empty row.** An empty four-column gap in a card is
the most visible layout defect on the page after the By node band, and it
costs nothing to close.

### 7. The limit disclosure

"Computed over at most N rows per query. Increase only within the configured
max." becomes "Computed over at most N rows per query."

The second sentence asks the reader to change a setting the page does not
expose, so it is a dead end rather than an instruction. The bound is still
disclosed, which is what the requirement is about.

## Risks / Trade-offs

**[The node options change is visible on the Logs and Prune pages]** → The
union is applied in the shared component, so all three pages behave
identically rather than only the one being reworked. The `log-viewing`
delta records the change so it is reviewed as a change and not discovered.

**[A thousand rows still reach the browser]** → The scroll region bounds the
*page*, not the payload. The by-node breakdown can still produce up to the
analysis limit of 1,000 rows, and they are all in the DOM. Making the payload
smaller is a data-layer change (a smaller analysis limit, or a top-N
breakdown) that would change what a breakdown reports, and is out of scope
here.

**[`maintainAspectRatio: false` changes how every chart is drawn]** → It is
merged into the options in one place, `chart_for/2`, so all three charts are
affected identically and the level, volume and node charts keep matching each
other. The chart *type* is untouched, so a pie is still a pie.

**[The chart is rebuilt on every re-render, as before]** → The hook's
`updated()` already tore down and recreated the chart on every patch. The
fixed-height frame does not change that, but it does mean the rebuild always
lands in a frame of the same size, so the chart does not visibly jump while
the scope changes.

**[`phx-update="ignore"` means the canvas's class is set once]** → The class
is static, so the first render's is the only one needed. If the height ever
becomes dynamic, the canvas can no longer carry it and the wrapper must.

**[The Analysis page's existing tests assert the removed summary row]** →
`analysis_live_test.exs` addresses `#analysis-active-nodes` in twenty places
across fourteen test cases. Those assertions move to the node options, which
is where the scope now lives. This is churn, not a behaviour change, and each
rewritten assertion is checking the same fact at its new address.

**[The control's "No known nodes." empty text is keyed on the known options]** →
`FilterControls.node_options/1` renders that text when `@options == []`. With
the union, a scope node the table no longer holds is rendered while the known
list is empty, so the text would appear next to a node badge. The condition
has to key on the rendered union instead, or the control says it has no nodes
while showing one.

**[The shared table density is a visible change to all three breakdowns]** →
It is the same compact step the prune page already uses, and it is applied to
all three breakdowns together, so they keep matching each other — which is
what the existing requirement already asks for.

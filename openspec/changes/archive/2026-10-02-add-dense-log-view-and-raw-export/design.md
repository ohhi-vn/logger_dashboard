# Design

## Context

See `proposal.md` - Why for motivation. What constrains the approach:

The viewer is a single LiveView, `LoggerDashboardWeb.LogLive.Index`, with all
markup inline in `render/1`. Rows are delivered through a LiveView stream
(`stream(socket, :logs, rows, reset: true)`), so the DOM patch is a stream
insert and the browser never re-renders the whole list.

Page size and page position are URL state, not assigns-in-session. `Filter`
parses `limit` and `offset` from the query string and clamps `limit` into
`[1, @max_limit]`. Every navigation is a `push_patch` that re-enters
`handle_params/3`, so there is exactly one place that decides what the page
shows.

Rows are read by `LoggerDashboard.Logs.LogRead.list_logs/2` through raw SQL
against ClickHouse. The rows arrive as maps of already-decoded values, so
rendering a row and rendering an exported line are both pure functions of a
decoded row. There is currently no export, no download, and no controller that
returns a file response; the only controllers are the homepage and the
framework's error views.

The project uses daisyUI as its component layer (`@plugin "daisyui/..."` in
`assets/css/app.css`, with `badge` and `table-zebra` classes already in use in
`core_components.ex` and the viewer). The tailwind build picks up classes out of
`lib/logger_dashboard_web`, so utility classes used in the template are
compiled without extra configuration.

One constraint from `openspec/config.yaml` carries into the design: text
predicates cannot be pushed down through Ash, so any query touching `message`
goes through `ClickhouseExLogger.Repo.query/3` with bound parameters. This change
adds no new predicate, so it does not add SQL.

## Goals / Non-Goals

**Goals:**

- Make the row's text fit one line without discarding data, and keep the
  discarded-in-view text reachable without a second query.
- Make the page size choices coarse enough to be useful for both skimming and
  wide history pulls, without breaking links that carry an old page size.
- Produce an export from the rows already in memory, so exporting cannot drift
  from what is on screen and cannot become a second, differently-parameterized
  query.
- Keep the change inside the existing single-LiveView, URL-driven shape. No new
  route, controller, or dependency.

**Non-Goals:**

- No whole-result-set export. Exporting a filtered set across all pages is a
  different feature with different performance characteristics; the spec scopes
  the export to the current page.
- No CSV, JSON, or format negotiation. One plain-text format is specified.
- No change to the read path, the raw-SQL predicate building, the filter form's
  other controls, the analysis page, or the prune page.
- No virtualized or windowed rendering. See the risk on 3000 rows.

## Decisions

### 1. Export from the page's own rows, not from a second query

The page's rows are held in a plain assign that `load_logs/2` sets alongside
every stream reset, so the export reads the exact rows the page is displaying.
(A LiveView stream is only consumable inside its own render — the engine marks
it consumable for the `for` comprehension — so the handler cannot read the
stream back with `Enum.to_list/1`. The assign and the stream are set together
in the one place that loads a page, so they cannot disagree.) The export is
therefore a pure function from a decoded row to a line of text, with no query,
no predicate construction, and no second parameterization that could disagree
with the page.

*Alternative considered:* re-run `LogRead.list_logs/1` inside the export handler
with an explicit limit/offset. Rejected — it duplicates the filter/offset
plumbing that `handle_params` already owns, and it introduces a second place
where a filter could be dropped, which would make the export quietly disagree
with the screen. It also doubles the query cost for a large page.

*Consequence:* the export is correct by construction with respect to the
current view, and costs no database round trip. The trade is that the export can
only ever cover the current page, which is exactly the specified scope.

### 2. Deliver the file with a pushed event and a client-side download

LiveView 1.2 has no server-side file-download primitive —
`Phoenix.LiveView.download/2` does not exist in the installed version or any
published one — so the export is delivered in two halves. The viewer's
`export` event builds the body from the rows already in memory and pushes it
to the client as a `logs-download` event carrying the body, the filename, and
the content type; a small `window` listener in `app.js` turns the body into a
Blob and downloads it through a transient anchor. No controller, route, or
`send_resp` plumbing is needed, and the viewer keeps its `phx-click`
convention: the export is one more clause in `handle_event/3` and one more
control beside the pagination summary.

*Alternative considered:* a controller action on the `:browser` pipeline, with
the filter state serialized into the path. Rejected — it would mean encoding
node, search, range, level, limit, and offset into a second URL shape and
re-parsing them in a second place, for a payload that is already in memory. The
existing router has no such endpoint and adding one would be the only new route
in the app.

*Consequence:* the download inherits the live view's session, and no new trust
boundary is introduced. The export is only reachable by a session that could
already see the page, so it exposes nothing that the page did not already
render. The cost is a few lines of client JavaScript whose browser-side effect
(the actual file save) is not assertable in LiveViewTest — tests cover the
pushed payload with `assert_push_event` and the body-building function
directly instead.

### 3. The export line is built by one formatting function, shared with the row

The line format — UTC timestamp, level, node, message, source location — is
close to what the row shows, but not identical: the row shortens the message,
the export must not. Rather than let two functions format the same fields
independently and drift, both go through one module that owns the field order
and the level/placeholder rules, parameterized by whether the message is
shortened.

This keeps the level placeholder and the source-location rendering in one place,
and makes the "exported message is not the shortened text" scenario a matter of
passing a flag rather than of a second implementation.

*Alternative considered:* format the export from the rendered DOM. Rejected —
that would couple the file's contents to CSS and to what happens to be visible,
and it would be untestable without a browser.

### 4. Multi-line messages are escaped, not emitted raw

A logger message may contain newlines, and stack traces routinely do. Emitting
the message verbatim would let one record's newlines push the following
record's fields onto continuation lines, so a downstream `grep` for a level or a
node would match a line that is not a record boundary.

The design escapes control characters — newline, carriage return, and tab become
their `\n`, `\r`, `\t` two-character escape sequences — so every record occupies
exactly one physical line and the original message stays reconstructible. This
is the same trade `grep`-able log tooling generally makes, and the spec's
"a multi-line message does not interleave with the next record" scenario is what
pins it.

*Alternative considered:* indent continuation lines under the message field.
Rejected — it preserves the raw bytes but reintroduces the ambiguity about
record boundaries, and a downstream consumer still has to know the indent
convention to parse it.

### 5. Row expansion is live-view state, and only one row is tracked

The expanded row is held in a single assign keyed by the row's DOM id, and
toggling pushes a `"toggle-expand"` event carrying that id. A single assign is
enough because expanding a second row collapses the first, which is the
expected behavior for a list where vertical space is the scarce resource.

The expanded panel shows the full untruncated message and, when present, the
metadata — the metadata `<details>` that used to sit inside every card becomes
part of the expanded panel rather than a second disclosure nested inside a
row.

*Alternative considered:* native `<details>` per row, which needs no live-view
state. Rejected — the current markup already nests a `<details>` inside a
streamed row, and driving it from a single assign keeps exactly one element
expanded and lets the expansion survive the row's own re-render without a
per-row hook. A native disclosure per row also has no place to guarantee that
only one is open.

### 6. The full message on hover is a native `title`, not a tooltip

The shortened message is exposed for hover through the element's `title`
attribute, which needs no JavaScript, no hook, and no extra request. It is a
coarse affordance, but the click-to-expand panel is the real access path and it
shows the message in full; the hover text is a convenience for scanning.

*Alternative considered:* a custom tooltip via a colocated hook. Rejected — it
would add a hook, an event, and styling for an affordance whose primary purpose
is already served by the expand panel.

### 7. Page-size policy is a two-constant change, not a normalization table

`Filter` currently clamps `limit` into `[1, @max_limit]` and falls back to
`@default_limit` on an unparseable value. The new page sizes need only
`@default_limit` to become 100 and `@max_limit` to become 3000. A `limit` that
is not one of the three offered values but is a positive whole number is still
honoured, so an existing bookmarked `?limit=50` keeps working.

The select is driven from the same list the spec names. Rather than duplicate
`["100", "500", "3000"]` between the template and the `Filter` module, the
offered values become a single exposed constant and the template renders it.

*Alternative considered:* normalize any non-offered `limit` to the default, so
the URL only ever carries one of three values. Rejected — it silently changes
the page size under an operator who is following an old link, which is exactly
the surprise this design is trying to avoid, and it buys only cosmetic tidiness
in the query string.

### 8. Density is a spacing change only; the accent and level text stay

The row's `border-l-4` level accent and the level badge are kept, because the
spec requires the level to remain readable as text and distinguishable by
accent. What changes is the row's own vertical padding, the gap between rows
in the stream container, and the removal of the per-row `rounded-r-md` and full
border in favour of a single hairline separator, so consecutive rows read as a
continuous list.

A `title` on the row is not relied on for the level, and the level stays a text
badge rather than becoming a color-only mark.

## Risks / Trade-offs

- **3000 rows in one live-view page** → The page renders 3000 rows into a
  single streamed container. That is a large DOM patch and a large message on
  the wire. Mitigation: the row is a single line with a small class list, and
  the stream is already the right delivery mechanism, so the cost is linear and
  bounded. If it proves slow in practice, windowed rendering is the follow-up —
  deliberately not built here, because nothing in the requirements needs it and
  it would complicate the stream and the export together.
- **Losing the "shows the whole message" guarantee is a real behavior
  regression for incident work** → Mitigation: the message is never discarded.
  It is on hover, in the expand panel, and in the export. The change trades
  default density for opt-in detail, and the expand panel is one click.
- **Export contents could drift from the screen** → Mitigation: decision 1
  makes the export render the same in-memory rows the page shows, and
  decision 3 makes both formats come from one function. A test asserts the
  exported line carries the untruncated message for a row whose displayed form
  is shortened.
- **The escape scheme is a lossy, non-obvious convention for consumers** →
  Mitigation: only the three control characters are escaped, so ordinary log
  text is byte-identical to the stored message, and the convention is stated in
  the spec scenario that requires it. This is a tradeoff accepted for
  greppability, not an oversight.
- **Existing links carrying `limit=25` or `limit=50` now render a page size the
  control does not show as selected** → Mitigation: the select is populated from
  the parsed `Filter`, so it displays the active size; if the active size is not
  in the offered list the control needs a way to represent it, which is
  verified during implementation rather than assumed here.
- **ClickHouse query cost at `limit=3000`** → Mitigation: the read path already
  supports an explicit limit through the same code path the 500 case used, so
  this is a larger number through an existing mechanism, not a new query shape.
  No new index or DDL is required, and the dashboard does not migrate.

## Migration Plan

1. Land the `Filter` constant change and the select values first. This is
   independently shippable and reversible by reverting two constants.
2. Land the row rendering and spacing change.
3. Land the export event and formatting module.

Each step is a self-contained commit, so the density change can be reverted
without losing the export. Rollback at any point is a revert of the relevant
commit; there is no migration, no persisted state, and no schema change to
reverse, so no data-loss consideration applies. The spec delta is archived
separately from the code and is not part of the rollback path.

## Open Questions

None. The page-size policy, the over-long message behavior, and the export line
format were each decided with the requester rather than deferred, and none of
the remaining implementation detail changes a specified behavior.

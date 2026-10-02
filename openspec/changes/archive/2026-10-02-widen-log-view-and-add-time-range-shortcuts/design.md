# Design

## Context

Three facts from the current implementation shape every decision here.

**Width is capped in two places, not one.** `Layouts.app` puts `max-w-6xl` on
both the header row (`layouts.ex:55`) and `<main>` (`layouts.ex:87`), so no page
can exceed 1152px. The Prune page then adds its own `max-w-3xl`
(`prune_live/index.ex:94`) inside that shell. The `dashboard-shell` spec already
requires a "consistent responsive content container" — today the two caps mean
it is not consistent.

**The filter contract is strict ISO8601 UTC, and the domain layer owns it.**
`Filter.parse_dt/1` (`filter.ex:196`) accepts only `DateTime.from_iso8601/1`,
and rejects anything else with a validation error. `Filter.parse/1` is the
single parser for the viewer, the Analysis page, and prune. That strictness is
load-bearing: the `log-viewing` spec requires that an unparseable bound be
*rejected with no query run*, and `prune_test.exs`, `filter_test.exs`, and
`prune_live_test.exs` all exercise strict strings.

**A native `datetime-local` input cannot express the current contract.** It
emits `2026-09-01T14:30` — no seconds, no offset — which
`DateTime.from_iso8601/1` rejects, and whose timezone is the browser's, not
UTC's. Any picker therefore needs a reconciliation step, and the reconciliation
has to land somewhere.

Existing tests that constrain the shape of the work: `log_live_test.exs`
asserts the pagination indicator renders the literal string
`Offset 25 · Limit 25`, and `prune_live_test.exs` asserts the `prune_node`
label contains both "Single node" and "one node only".

## Goals / Non-Goals

**Goals:**

- One container governs width, and it uses the viewport.
- The URL contract for time bounds stays strict ISO8601 UTC, so existing
  `/logs?from=...&to=...` links and the spec's rejection scenarios are
  untouched.
- Shortcuts resolve against the server clock at request time.
- One control serves every page that filters by time.
- No new JavaScript dependency, and the page still works with JS unavailable.

**Non-Goals:**

- Changing the SQL predicate set, `Filter.predicates/1`, the raw read path, or
  the ClickHouse schema.
- Loosening `Filter.parse_dt/1`. A native picker reading as UTC server-side
  would widen the accepted wire format to offset-less datetimes, which would
  make the domain layer's contract depend on which widget produced the string.
  Rejected — see D2.
- A shared log-line component shared with Analysis. Only the *filter controls*
  are shared; the row markup stays in the viewer.

## Decisions

### D1: Shell-wide width, not a Logs-only escape hatch

Drop `max-w-6xl` from both the header row and `<main>` in `Layouts.app`, and
drop `max-w-3xl` from the Prune page. Keep the existing `px-4 sm:px-6 lg:px-8`
horizontal padding, so content stops at the padding edge rather than at a fixed
measure.

*Alternative rejected:* give only the Logs page a wider inner container while
leaving the shell at `max-w-6xl`. It is a smaller diff, but it leaves the shell
container inconsistent with the page that breaks out of it — the nav would be
centered at 1152px above full-bleed content — and it leaves Prune doubly-capped,
which is the inconsistency `dashboard-shell` already complains about.

*Consequence:* the header loses its max width too, so nav and content stay
aligned. Homepage and Analysis also widen. Analysis's chart cards get more
room, which is an improvement rather than a regression, and both pages keep
their own padding.

### D2: The picker is a second control over the existing ISO8601 field, not a replacement

Each datetime bound keeps its named text field holding strict ISO8601 UTC. A
native `type="datetime-local"` input is rendered beside it, unnamed (so it
never submits), and a colocated `.UtcDateTime` hook keeps the two in sync:

- **on mount**, read the text field's ISO value, format it as
  `YYYY-MM-DDTHH:MM`, and assign that to the picker;
- **on picker change**, format the offset-less picker value as
  `YYYY-MM-DDTHH:MM:SSZ` and write it into the text field;
- **on text field change**, parse the ISO value and assign UTC wall-clock to the
  picker, or clear it when unparseable.

Because the text field is what the form submits and what the URL carries, the
server never sees an offset-less datetime and `Filter.parse_dt/1` is untouched.
The field IDs the tests use (`filters[from]`, `prune[from]`, …) keep their
current names and values.

*Alternatives rejected:*

- *Widen `parse_dt/1` to accept offset-less input read as UTC.* Simplest
  possible change — no JS at all. Rejected: it makes the accepted wire format
  depend on which widget was used, and it puts a timezone decision in the
  domain layer that the picker is better placed to own. It would also leave the
  picker showing UTC wall-clock to a user outside UTC, with no way to tell.
- *Convert to local time client-side and submit local.* Better ergonomics for
  the user, but it makes the submitted value depend on the client's timezone,
  so the same URL means different instants for different operators and the
  server-side tests cannot cover it.

*Consequence:* with JS unavailable the text fields still work and the picker
sits empty until the page initialises it. Progressive enhancement, not a
regression.

*Refinement made during apply.* Two details differ from the first draft of this
decision, both forced by the framework's actual behavior:

- The wrapper carries `phx-hook` but **not** `phx-update="ignore"`. LiveView
  does not descend into an element's children when that element is marked
  `ignore`; it merges only the element's own attributes. Marking the wrapper
  ignored therefore made the server unable to replace the bound fields' values,
  so a shortcut could never update the range it had just resolved. The hook only
  mirrors values onto the picker and never creates or replaces DOM, so the
  "hook owns its DOM" condition that normally calls for `ignore` does not hold
  here. The hook gained an `updated()` callback so the picker re-syncs after a
  server patch as well as after typing.
- The `phx-hook` value is the module-qualified name
  (`LoggerDashboardWeb.RangeInputs.UtcDateTime`), derived from `__MODULE__`. A
  colocated hook is registered in the bundle under `"<defining module>.<name>"`
  and the client looks the attribute up in that map verbatim — it does not
  expand a short `.UtcDateTime` back to its module, so the short form the
  framework's own docs show would silently never attach. Deriving the string
  from `__MODULE__` keeps a module rename from leaving a hook pointing at
  nothing.

### D3: Shortcuts are a `preset` param resolved server-side, not resolved client-side into the URL

A shortcut button `push_patch`es with `preset=<id>` and no `from`/`to`. The
server resolves the preset to a concrete range against `DateTime.utc_now()`
during `Filter.parse/1`, and the resolved bounds are then what the page shows in
the text fields and the picker.

*Alternative rejected:* resolve to concrete instants at click time and push
those. Simpler, but a bookmarked "last hour" URL becomes a fixed hour the
moment it is created — the operator reloads and the window has quietly slid
out of relevance. For a page whose whole job is "what just happened", the URL
should carry the intent, not a stale resolution.

Precedence rule, stated once: **when `preset` is present it determines both
bounds and any explicit `from`/`to` in the same request is ignored.** The
shortcut click is the more recent and more explicit action, and resolving over
a half-typed bound would be surprising. The corollary is that the filter
form's submit handler drops `preset` from the params it sends, so a manual
edit is never silently overwritten — clicking a shortcut discards the previous
range, and typing a bound replaces the shortcut.

### D4: One duration vocabulary in `Filter`, two preset families

`Filter` owns the vocabulary and the resolution, because `Filter` already owns
param parsing for all three pages:

```elixir
@presets %{
  "window" => [{"10m", {10, :minute}}, {"1h", {1, :hour}}, {"6h", {6, :hour}},
               {"24h", {24, :hour}}, {"7d", {7, :day}}],
  "age" => [{"1d", {1, :day}}, {"3d", {3, :day}}, {"7d", {7, :day}},
            {"30d", {30, :day}}, {"90d", {90, :day}}]
}
```

`Filter.presets/1` returns a family's ordered list and `Filter.preset_id/2`
qualifies a bare id as `"<family>:<id>"`. `Filter.resolve_preset/2` takes
`(preset, now)` and returns `{:ok, {from, to}}` — `{now - duration, now}` for a
window preset, `{nil, now - duration}` for an age preset, `{:ok, {nil, nil}}` for
an absent one, and `{:error, message}` for an unrecognized id. The window/age
distinction is a property of the table, not a branch in the resolution function.
`Prune` calls the same function with an age preset, so a shortcut on the prune
page needs no prune-specific duration knowledge. An unrecognized id returns
`{:error, ...}` and `parse/1` propagates it, which satisfies the spec's "no query
on unknown shortcut" without a separate check.

*Refinement made during apply.* Both families want a `7d` reading, and "last 7
days" and "older than 7 days" are different ranges, so a bare `7d` is ambiguous
and `resolve_preset/2` cannot have both meanings. Ids are therefore namespaced as
`window:7d` and `age:7d`. This keeps `parse/1` free of any notion of which page
it is serving — the preset id is self-describing in the URL, which is also what
makes the URL unambiguous to read.

"All time" is not a preset; it is the absence of one. The button pushes with
`from`, `to`, and `preset` all dropped.

*Note on the domain layer:* resolving `preset` into `from`/`to` inside
`parse/1` means the resulting `Filter` struct is indistinguishable from one
parsed from explicit bounds. `predicates/1` is therefore untouched and still
emits the same clause order that `filter_test.exs` asserts verbatim. The
`preset` identifier is kept as a struct field purely so the UI can mark the
active shortcut, and `Filter.to_params/1` renders a filter back to the string
params a form and a URL need — including the instants a preset resolved to, so
the inputs show what was applied rather than what was merely requested.


### D5: Shortcuts fill fields only — the mutation path is structurally untouched

The prune page's shortcut buttons are `phx-click` events that `push_patch`
with the new bound. They do not call `Prune.parse/1`, `Prune.run/1`, or
anything in `handle_event("preview")`. The existing flow is unchanged: fill the
form, submit, see `#prune-confirm`, then `#prune-confirm-button` dispatches the
delete.

*Rationale:* an age shortcut is an attractive way to turn a mistyped-URL
`ALTER TABLE ... DELETE` into a one-click operation. The structural guarantee —
the only handler that reaches `Prune.run/1` is `handle_event("confirm")`, which
requires a prior successful `handle_event("preview")` — is worth more than any
runtime check, so it is preserved rather than re-verified at each call site.
This also satisfies the spec scenarios that a shortcut-only destructive request
is rejected and that an unset `scope` still fails.

### D6: The log row is a two-line grid with a level accent

Replace the `<article>` card with a row that lays out as a header line
(`node`, `timestamp`, `level`) above a body line (`message`, source location).
The level contributes both a colored left border stripe and a badge carrying
the level as text; the badge means level is never conveyed by color alone. The
accent colors come from the same daisyUI level vocabulary the page already
uses (`badge-error`/`badge-warning`/`badge-info`/`badge-ghost`), so no new
palette is introduced and the row accent stays consistent with the Analysis
level breakdown.

Metadata renders on the body line when non-empty, behind a `<details>` so it
does not compete with the message on a dense list. This closes the long-standing
gap where the `log-viewing` spec has required `metadata` in the row contents and
the viewer never rendered it.

*Alternative rejected:* a terminal-style single monospace line per row. It reads
well for short messages, but Elixir log messages are frequently multi-line
stack traces and structured payloads; a single line either truncates them or
needs its own expansion affordance. The two-line form gives the metadata and
location a home without taking space away from the message.

*Consequence:* the `#logs-list` stream container and its per-row stream IDs are
unchanged, so streaming behavior is untouched. The pagination indicator keeps
its `Offset N · Limit N` wording to avoid breaking
`log_live_test.exs:138`.

### D7: One shared control module, imported via `html_helpers`

A new `LoggerDashboardWeb.RangeInputs` module exports the bound control (label
+ text field + picker + colocated hook) and the shortcut button row. It is
imported in the `:html_helpers` block of `logger_dashboard_web.ex` so all three
LiveViews can use it, matching how `CoreComponents` is already made available.

The module takes the field, an ID prefix for DOM ids, and the preset family it
should offer, so the viewer/Analysis pass `:window` and Prune passes `:age`. A
page therefore cannot accidentally offer an age shortcut that sets `from`, or a
window shortcut that ignores its scope.

*Note:* the Log and Analysis pages currently duplicate the active-nodes chip row
and clear-nodes button verbatim, differing only by id prefix. That duplication
is adjacent to this change but not part of it; consolidating it is left alone
rather than widening the diff.

## Risks / Trade-offs

- **Shortcut URLs change what they mean over time.** A bookmarked
  `/logs?preset=1h` returns a different window on every load by design. →
  Mitigation: the resolved UTC `from`/`to` are always visible in the text
  fields, so the operator can see the window that was actually applied and
  promote it to a fixed range by submitting the form.
- **The picker is inert without JS.** → Mitigation: the named field is the text
  input, not the picker, so every path that matters for no-JS and for tests
  goes through a control that has always worked. The picker degrades to an
  empty widget rather than to a broken form.
- **Timezone confusion in the picker.** A UTC wall-clock shown to an operator in
  UTC+7 is easy to misread as local. → Mitigation: the label says UTC on both
  the picker and the text field, and the text field always shows the ISO string
  it will submit, so the two are cross-checkable.
- **`Filter.parse/1` precedence is a new rule on a shared parser.** A caller
  that sends both `preset` and `from` gets the preset's bounds, not the sent
  ones. → Mitigation: `filter_test.exs` covers the precedence explicitly, and
  only the three filter LiveViews construct these params.
- **Widening the shell affects pages this change does not target.** →
  Mitigation: the only width-related change is removing a max-width; every page
  keeps its padding and its own inner layout. Analysis's charts gain width
  rather than losing it.
- **`metadata` rendering can add noticeable height to a dense list.** →
  Mitigation: it is behind a collapsed `<details>` and only renders when
  non-empty, so rows without metadata keep the same height as today.
- **Full-suite proof needs ClickHouse.** `:clickhouse`-tagged tests are not
  excluded, so `mix precommit` fails without a running instance. → Mitigation:
  bring ClickHouse up before the final verification, per the project context.

## Migration Plan

No data migration and no rollback concern: the schema is untouched and DDL
stays upstream. Rollback is reverting the commit; `preset` is additive, so URLs
written by the new code keep working against the old code only as explicit
bounds — a `preset`-only URL against old code would parse as an unbounded
filter, which is the correct conservative behavior for the viewer.

## Open Questions

None. Every question that would have changed the specs, the approach, or the
task breakdown was resolved with the user before this document was written.

# Design

## Context

See proposal.md for why. The technical shape of the problem:

`AshDyan.run/2` returns one uniform shape for every analysis type
(`deps/ash_dyan/lib/ash_dyan/result.ex`):

```elixir
%AshDyan.Result{type: :time_bucket, labels: [...], series: [%{name: String.t(), data: [...]}]}
```

`series` is a **list**, and how many entries it has depends on `group_by`:

- `:frequency` with no `group_by` (`level_frequency/2`, `node_frequency/2`)
  produces exactly one series (`Formatter.frequency/2`, the `group_by: []` clause).
- `:time_bucket` with `group_by: [:level]` (`volume_over_time/3` called with
  `split_by_level: true`) pivots into **one series per level**
  (`Formatter.pivot/5`).

`AnalysisLive.Index.pairs/1` assumed the single-series case
(`[%{data: data} | _]`), which is why the volume table silently drops levels.

Three facts about the installed dependency constrain the fixes:

1. `Formatter.frequency/2` emits `labels = Map.keys(counts) |> Enum.sort()` — it
   sorts labels **alphabetically** and derives `data` in that same order. Any
   value ordering has to be requested.
2. `Formatter.post_process/2` implements `sort_by` / `sort_order` / `top`, with
   `sort_order` defaulting to `:desc`, and reorders `labels` and **every** series'
   `data` in parallel. This is the supported way to order a frequency result.
3. `AshDyan.Analysis.TimeBucket.supports_presentation?/1` returns `false` for
   `:sort_by` and `:top`, so `Request.validate_presentation_supported/2` would
   **reject** a `time_bucket` request carrying `sort_by` with an `AshDyan.Error`.
   Bucket labels must stay chronological and `sort_by` must not be sent there.

On the form side: `Phoenix.HTML.Form.options_for_select/2` emits no `selected`
attribute when the value is `nil`, so a `<select>` built from a form that lacks
the key renders with nothing marked and the browser displays the first option.
Verified against the pinned `phoenix_html` 4.1:

```
nil  -> <option value="hour">hour</option><option value="day">day</option>
day  -> <option value="hour">hour</option><option selected value="day">day</option>
```

Constraints carried from the project context: no DDL change, no dependency
change, raw SQL stays confined to the read and prune paths (none of this change
touches SQL), and `mix precommit` must pass against a running ClickHouse.

## Goals / Non-Goals

**Goals:**

- One helper that turns any `AshDyan.Result` into rendered rows without dropping
  a series, so the same helper serves the level, volume, and node tables.
- The bucket shown in the control is the bucket the query used, including when
  the requested bucket was not a real one.
- A rejected request renders no results.
- Descending-by-count ordering expressed as a property of the analysis request,
  not of one page.
- Regression tests that would have caught each of the five defects.

**Non-Goals:**

- Which buckets the page offers. `Analysis.buckets/0` declares five; the page
  offers `hour`/`day`. That is a product decision (a `minute` bucket over a 7-day
  window is 10 080 labels) and is left exactly as it is.
- `Analysis.buckets/0` and `Analysis.default_bucket/0` are public but called only
  inside `Analysis`. Not dead yet — `default_bucket/0` is the fallback — and not
  worth a visibility change in a bug-fix change.
- The `log-viewing` and `log-pruning` observations listed in proposal.md.
- Changing what the chart draws. The chart already renders every series
  correctly; only the table was wrong.

## Decisions

### Render a label × series grid, not a list of `{label, value}` pairs

Replace `pairs/1` with a helper returning `{series_names, rows}` where each row
is `[label | one_value_per_series]`. The template renders a `<thead>` of series
names over rows whose first cell is the label.

*Alternative: stop splitting volume by level.* One line, and `pairs/1` would then
be correct. Rejected: the split is the useful reading of "volume over time" and
`log-analysis` explicitly allows it; dropping information to accommodate a
rendering helper inverts the fix.

*Alternative: one row per `(label, series)` pair.* Rejected: it transposes the
table, so reading one bucket's level mix requires scanning every `level`-th row,
and the table grows by a factor of the level count. A column per series matches
the chart's legend and reads across a bucket in one row.

One helper for all three tables keeps them consistent — the same class of bug
cannot reappear on one table and not another.

### Put the effective bucket in the form, and get it from `Analysis`

`Analysis.normalize_bucket/1` becomes public. `handle_params/3` normalizes once,
puts `Atom.to_string(bucket)` into the form params alongside
`Filter.to_params/1`'s output, and passes the atom to `Analysis.volume_over_time/3`.
`normalize_bucket/1` is already idempotent, so the second normalization inside
`volume_over_time/3` is a no-op.

*Alternative: have `Analysis.volume_over_time/3` return `{bucket, result}`.* The
bucket would then never be able to disagree with the request. Rejected: it
changes a public signature for one caller and reads worse at the call site; the
disagreement is a form-rendering problem, and the fix belongs where the form is
built.

*Alternative: leave the raw param in the form.* Rejected: that is the bug — the
control would keep showing `hour` for `?bucket=zzz` while the server ran the
default.

### Clear result assigns on the rejected path, mirroring `LogLive.Index`

`handle_params/3`'s `{:error, _}` branch assigns `nil` to `levels`, `volume`,
`nodes`, `analysis_error` and `%{}` to `charts`, with `filter_error` assigned
last so it cannot be clobbered.

`LogLive.Index` already clears its result assigns on its rejected path, so this
follows an established in-repo pattern rather than introducing one. A private
`clear_results/1` keeps the branch a single pipe.

### Order frequency results with `sort_by: :value`, in `Analysis`

`level_frequency/2` and `node_frequency/2` add `sort_by: :value` and
`sort_order: :desc` to their request maps. `sort_order: :desc` is the dependency's
current default, but it is sent explicitly so the ordering this spec requires
does not silently invert if a future release changes that default. `volume_over_time/3`
is untouched — passing `sort_by` there would make
`Request.validate_presentation_supported/2` reject the request and break the page.

`Analysis.normalize_unknown/1` runs after `post_process/2` has already reordered
`labels`, and maps values rather than positions, so it does not disturb the
ordering.

*Alternative: sort in the LiveView after the result arrives.* Rejected: it
duplicates a capability the dependency owns and tests, and leaves `Analysis`'s
own contract order-free while the page is the only caller that happens to want an
order. Ordering is a property of the request.

### Disclose the capped limit after the query

`load_analysis/3` assigns `Analysis.applied_limit(limit: limit)` instead of the
bare `limit`, matching `mount/3`. With the current `max_limit` of 10 000 the two
happen to agree; the point is that the disclosure stops depending on that.

### Test through rendered structure, with seeded rows

`AnalysisLive.Index`'s existing tests only assert element presence, which cannot
distinguish "dropped three of four series" from "rendered four series" — that is
why the defect survived. The new tests need rows, so they live in a new
`analysis_live_data_test.exs` with `async: false` and `@moduletag :clickhouse`,
following `test/logger_dashboard/logs/analysis_test.exs`: seed rows under a unique
node tag through `ClickhouseExLogger.Insert.insert/1`, then scope the page to
that node so concurrent tests cannot see them.

Each series header carries `data-series={name}` and each value cell carries
`data-series={name}`, so a test asserts *which* series rendered via a selector
rather than by matching table text. The bucket `<option>` carries `selected`, so
the bucket test is a `#filters_bucket option[selected]` assertion.

Tests reference key DOM ids (`#filters_bucket`, `#analysis-volume`,
`#analysis-nodes`, `#analysis-levels`, `#analysis-filter-error`,
`#analysis-missing`) rather than page text.

## Risks / Trade-offs

- **A volume result with four levels yields a five-column table.** At
  `max_group_by(2)` and one `group_by`, four is the ceiling, so the table stays
  readable. If someone later adds a second `group_by`, the column count doubles
  and the table wants a different presentation → acceptable; the chart beside it
  degrades the same way, so the two stay comparable.

- **Descending order changes what existing links and tests show.** No existing
  test asserts node-table order, and no requirement asks for alphabetical order,
  so nothing regresses. Anyone reading the table for a node by name rather than
  by volume now scans a differently ordered list.

- **`sort_by: :value` is a new field in the `AshDyan.run/2` request map.** If a
  future AshDyan release changes the default `sort_order`, the ordering becomes
  ambiguous. Sending `sort_order: :desc` explicitly removes that dependency at
  the cost of one more key, which is why both options are set.

- **`Process.sleep/2_000` after seeding**, copied from `analysis_test.exs`,
  conflicts with the project's "avoid `Process.sleep`" guideline. There is no
  monitor-able handle for ClickHouse's `async_insert` visibility delay — the
  insert call has already returned `{:ok, 1}` before the rows are queryable — so
  the guideline is not achievable here. Consistency with the existing ClickHouse
  tests is the better trade; noted rather than silently accepted.

- **Clearing results on the rejected path is a visible change**: a user who
  submits a bad bound now sees the previous numbers disappear. That is the
  intent — the alternative is numbers that do not correspond to anything the
  server computed.

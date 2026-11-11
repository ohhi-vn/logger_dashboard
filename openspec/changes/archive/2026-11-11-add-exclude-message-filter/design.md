# Design

## Context

`LoggerDashboard.Logs.Filter` already owns `search` parsing, term splitting,
wildcard translation (`search_patterns/1`), and predicate emission. `LogRead`
and `Analysis` both read through `Filter.predicates/1`, so adding a predicate
there propagates to both pages without touching the read path. The shared
`FilterControls.search/1` component renders the search input and its syntax
help.

## Goals / Non-Goals

**Goals:**
- Add an `exclude` filter that mirrors `search` in syntax and term combination.
- Reuse the existing wildcard translation rather than duplicating it.
- Keep all SQL parameterized.

**Non-Goals:**
- No change to page sizes, pagination, or export.
- No exclude control on the Prune page.
- No new dependency.

## Decisions

### Predicate shape

`Filter` gains an `exclude` field (string, default `""`). Parsing is identical
to `search`. Predicate emission calls `search_patterns/1` on the exclude value
and adds one clause:

- one pattern: `message NOT ILIKE ?`
- several patterns: `NOT (message ILIKE ? AND message ILIKE ? AND ...)`

This mirrors search's AND semantics: a row is excluded only when it matches
every exclude term, exactly as a row is included only when it matches every
search term.

### Shared control

The existing `FilterControls.search/1` component is reused for exclude with
`label="Exclude"` and a distinct placeholder. No new component is needed; the
help text already states the shared syntax. `exclude` gets its own form field
and URL param named `exclude`.

### Prune handling

`Prune.parse/1` already deletes `search`; it will also delete `exclude`, so a
prune never filters by message. This keeps the prune safety model unchanged.

### Handoff

The Logs-to-Analysis link adds `exclude` to its carried params, alongside
`search`.

## Risks / Trade-offs

- [Term combination ambiguity] Operators might expect exclude terms to combine
  with OR. The spec resolves this by mirroring search (AND), and the control's
  help text states the combination.
- [Empty exclusion] An empty exclude must add no predicate; `search_patterns/1`
  already returns `[]` for blank input, so the guard is the same as for search.

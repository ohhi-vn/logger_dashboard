# Tasks

## 1. Distinct node options read path

- [x] 1.1 Add bounded distinct-node raw query reusing bound parameters and the existing result-error shape, and verify a ClickHouse unit test asserts ordered non-null nodes and nil-rows-as-error
- [x] 1.2 Load node options in `LogLive` alongside page rows without changing the active filter semantics, and verify a LiveView test shows options independent of the current page and empty-table fallback to text input

## 2. Click-to-filter interactions

- [x] 2.1 Render node options as clickable toggles plus the existing comma input and clear action, wiring clicks through URL-param patch that preserves search/range/level, and verify LiveView tests for add-toggle, remove-toggle, last-node-returns-to-all, and other-filters-preserved
- [x] 2.2 Render levels (`all`, `error`, `warning`, `info`, `debug`) as clickable options that set the level param, and verify LiveView tests for click-selects-level, click-replaces-level, and click-all-clears-predicate

## 3. Per-row copy full info

- [x] 3.1 Add per-row copy action pushing the `LogLine.format/1` text (timestamp, level, node-or-placeholder, untruncated message, location) without changing filters/position/rows, and verify a LiveView test asserts the pushed payload equals the export-format line including placeholder and untruncated message cases
- [x] 3.2 Add clipboard window listener in `app.js` mirroring `phx:logs-download` with failure flash fallback, and verify manual browser check copies text and denied-permission shows a message while the expanded panel still holds the same text

## 4. Columns, resize, and expand

- [x] 4.1 Restructure rows into explicit timestamp/level/node/message/location/action columns keeping single-line truncation, hover full text, level accent plus text, and tight list spacing, and verify LiveView test asserts column order and one-line row rendering
- [x] 4.2 Add client-side column resize handles whose widths never reach the server or URL and survive expand/collapse, and verify manual browser check that resizing changes width only and expanding preserves widths and filters/position
- [x] 4.3 Keep single-row expand/collapse for full message plus metadata via re-insert at index, and verify LiveView tests for expand-shows-message, metadata handling, and page-otherwise-unchanged

## 5. Verification

- [x] 5.1 Add/extend LiveView and unit coverage for all new scenarios in `specs/log-viewing/spec.md` and verify the focused test files pass with a running ClickHouse
- [x] 5.2 Run `mix precommit` with ClickHouse available and verify no failures before requesting review

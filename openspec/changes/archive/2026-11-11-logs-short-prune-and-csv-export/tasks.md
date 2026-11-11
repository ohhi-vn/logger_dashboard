# Tasks

## 1. CSV rendering in LogLine

- [x] 1.1 Add `csv_header/0`, `csv_row/1`, and `csv_page/2` to `LoggerDashboard.Logs.LogLine`, with RFC 4180 quoting and JSON-serialized metadata, and verify `test/logger_dashboard/logs/log_line_test.exs` covers commas, quotes, newlines, and empty metadata
- [x] 1.2 Keep `format/1` and `format_page/1` unchanged for copy-row, and verify existing plain-text tests still pass

## 2. Row selection in the Logs LiveView

- [x] 2.1 Add `@selected_ids` assign (empty `MapSet`) on mount and reset it in `apply_filter_params/2`, and verify a filter or page change clears selections
- [x] 2.2 Render a per-row checkbox and a select-all checkbox in `log_live/index.ex`, wired to `toggle-select` and `select-all-rows` events, and verify `has_element?/2` finds them in `log_live_test.exs`
- [x] 2.3 Implement `handle_event/3` for `toggle-select` and `select-all-rows` without patching filters or position, and verify selection state updates in tests

## 3. CSV export

- [x] 3.1 Change `@export_filename` to `logs-export.csv` and the pushed content type to `text/csv; charset=utf-8`, and verify the export event payload in tests
- [x] 3.2 Build the export body from selected rows when any are selected, otherwise all `@page_rows`, using `LogLine.csv_page/2`, and verify both branches in `log_live_test.exs`
- [x] 3.3 Verify an empty page exports a header-only file and that a multi-line message stays in one CSV record

## 4. Short prune from the Logs page

- [x] 4.1 Add `@prune_review`, `@prune_error`, and `@prune_result` assigns plus a "Prune current filter" button, and verify the button renders on `/logs`
- [x] 4.2 Implement `prune` event that builds prune params from the current filter, calls `Prune.parse/1` and `Prune.review/1`, and stores the review or error, and verify the review panel shows count, per-node split, and sample
- [x] 4.3 Implement `confirm-prune` and `cancel-prune` events calling `Prune.run/2` and refreshing the page on success, and verify delete-then-refresh behavior in tests
- [x] 4.4 Block short prune for invalid or unbounded filters and surface the error, and verify no delete runs in those cases

## 5. Integration verification

- [x] 5.1 Run `mix precommit` and fix any failures, including ClickHouse-backed suites when a server is available
- [x] 5.2 Update `log_live_test.exs` assertions for CSV filename, content type, selection, and short prune, and verify they pass

# Tasks

## 1. Page size

- [x] 1.1 In `LoggerDashboard.Logs.Filter`, change `@default_limit` to 100 and `@max_limit` to 3000, and expose the offered page sizes `["100", "500", "3000"]` as a public constant alongside `default_limit/0`; verify `mix compile` is clean and no other module references the old literal values
- [x] 1.2 Confirm the existing clamp in `parse_pagination/1` already yields the specified policy — a positive whole `limit` is honoured, one above 3000 is capped to 3000, and an unparseable one falls back to 100 — and add `filter_test.exs` cases for `limit=25` (honoured), `limit=5000` (capped to 3000), and `limit="abc"` (falls back to 100); verify those cases pass
- [x] 1.3 Replace the hardcoded `options={["25", "50", "100"]}` on the `#logs-filter-form` per-page select with the new `Filter` constant and confirm the select's displayed value is driven by the parsed `Filter` rather than a literal, so an active `limit=25` reached from an existing link is represented rather than blank or reset; verify the rendered select shows exactly 100, 500, and 3000 as options and shows 100 as active on a URL with no `limit`
- [x] 1.4 Update the `#logs-pagination` summary text so it no longer hardcodes the old sizes, and add `log_live_test.exs` cases asserting `Offset 0 · Limit 100` by default, that patching to `?limit=500` renders `Limit 500`, and that `?limit=5000` renders `Limit 3000`; verify these cases pass without needing ClickHouse

## 2. Shared log line formatting

- [x] 2.1 Add a module that owns the exported line format and the row's field order in one place, per design decision 3: UTC timestamp, level, node, message, source location, with an explicit placeholder for a missing node and the source location omitted when the row has none
- [x] 2.2 In that module, escape newline, carriage return, and tab in the message to their two-character `\n`, `\r`, `\t` sequences so each record occupies exactly one physical line, per design decision 4; verify a unit test covering a message containing newlines, a message containing tabs, and an ordinary message asserting the ordinary message is byte-identical to the stored value
- [x] 2.3 Give the module a way to format with and without message shortening so the row and the export share the field order but the export never receives a shortened message; verify a unit test asserting the two forms differ only in the message and are identical in every other field

## 3. Single-line row rendering

- [x] 3.1 Collapse the row in `LogLive.Index`'s `render/1` from the two-line card to a single line carrying timestamp, level, node, message, and source location, tagged `data-role="log-line"`, and remove the now-dead `log-header` and separate message and source-location lines; verify a `:clickhouse`-tagged test asserting `data-role="log-line"` exists and `data-role="log-header"` does not
- [x] 3.2 Constrain the row to a single line's height: apply a non-wrapping, overflow-hidden, text-ellipsis treatment to the message so it shortens with a trailing ellipsis instead of growing the row, and verify a `:clickhouse`-tagged test seeding a 200-times-repeated message asserts the row still renders one line
- [x] 3.3 Expose the untruncated message on hover via the element's `title` attribute per design decision 6; verify the rendered row for a shortened message carries a `title` holding the full message
- [x] 3.4 Reduce density: tighten the row's vertical padding, cut the gap in the `#logs-list` stream container, and replace the per-row rounded border with a single hairline separator so consecutive rows read as a continuous list, while keeping the `border-l-4` level accent and the level text badge intact; verify the level accent and badge assertions in the existing row-shape suite still pass unchanged

## 4. Row expansion

- [x] 4.1 Add an `expanded_id` assign to `LogLive.Index`, initialised to `nil` on mount, and a `handle_event/3` clause for toggling a row by its DOM id that collapses any previously expanded row when a different one is opened; verify no page state outside that assign changes on toggle
- [x] 4.2 Add a per-row expand toggle carrying `id="logs-expand-<dom_id>"` that is reachable by keyboard and reports its expanded state to assistive technology; verify a `:clickhouse`-tagged test clicks the toggle and asserts the expanded panel appears
- [x] 4.3 Render the expanded panel at `id="logs-expanded-<dom_id>"` showing the full untruncated message and, when the row's metadata is non-empty, that metadata, moving the metadata disclosure out of the collapsed row and into the panel; verify a `:clickhouse`-tagged test asserting metadata is absent while collapsed and present with its `user_id` value after expansion
- [x] 4.4 Omit the metadata section entirely for a row whose metadata is empty rather than rendering an empty disclosure; verify a `:clickhouse`-tagged test for a row with empty metadata shows the full message and no metadata element
- [x] 4.5 Confirm expansion does not disturb the page: verify `log_live_test.exs` cases asserting the filter params, the offset, and the row count are unchanged before and after a toggle

## 5. Raw text export

- [x] 5.1 Add a `handle_event/3` clause in `LogLive.Index` for the export that reads the current page's rows from the page's own row list — assigned alongside the stream reset in `load_logs/2`, because a LiveView stream is only consumable inside its own render — rather than issuing a second query, per design decision 1; verify no call to `LogRead.list_logs/1` is reachable from the export path
- [x] 5.2 Build the file body by joining the formatted lines with newlines in the same newest-first order as the page, and push it to the client as a `logs-download` event carrying the body, the filename, and the content type, which `app.js` downloads as a Blob with a filename identifying it as a log export, per design decision 2; verify a test asserts the pushed payload's content type and filename
- [x] 5.3 Add an export control with `id="logs-export"` beside the `#logs-pagination` summary, and verify a test finds `#logs-export` and that clicking it pushes the download event
- [x] 5.4 Verify the export covers exactly the current page: add a `:clickhouse`-tagged test that advances to a later page before exporting and asserts the downloaded body contains that page's rows and none from the first page
- [x] 5.5 Verify the export honours the active filters: add a `:clickhouse`-tagged test that exports while a node scope and level are active and asserts every exported line matches them
- [x] 5.6 Add cases asserting each exported line carries the UTC timestamp, level, node, and message; that a row with source location carries it; that a row with no node shows the explicit placeholder rather than an empty field; and that a row whose message is shortened on screen exports the full untruncated message
- [x] 5.7 Add a case asserting a message containing newlines is escaped so the following record's fields do not interleave into it, and that the lines remain in newest-first order
- [x] 5.8 Add a case asserting exporting an empty page succeeds and yields a file with no rows, and that triggering the export leaves the filters, page position, and rows on the page unchanged

## 6. Verification

- [x] 6.1 Run the non-ClickHouse tests and verify they pass without a running ClickHouse
- [x] 6.2 Bring up ClickHouse, run `mix clickhouse_ex_logger.migrate`, and run the full suite including the `:clickhouse`-tagged tests; verify the pre-existing viewer row-shape and pagination suites have been rewritten to the new single-line structure and new page sizes rather than left asserting the old ones
- [ ] 6.3 Run `mix precommit` and fix any reported issues
- [x] 6.4 Load `/logs` in a browser and confirm by eye that rows read as a continuous dense list, a long message shows an ellipsis, clicking a row reveals the full message and its metadata, the per-page select offers 100, 500, and 3000 with 100 active by default, and the export downloads a file whose lines match the rows on screen

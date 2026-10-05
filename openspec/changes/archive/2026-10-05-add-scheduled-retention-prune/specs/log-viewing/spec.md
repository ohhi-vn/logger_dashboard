# Spec Delta

## MODIFIED Requirements

### Requirement: Paginated newest-first browsing

The system SHALL paginate log results with limit/offset and preserve active filters across pages. Pages SHALL be drawn from the complete set of rows matching the active filters.

The per-page row count SHALL be selectable from 100, 500, and 3000, and 100 SHALL be used when no page size is specified. A page SHALL hold at most 3000 rows.

A page size carried in the URL that reads as a positive whole number SHALL be honoured, so a page size that is no longer offered but still reachable by an existing link keeps working. A page size above 3000 SHALL be capped at 3000. A page size that does not read as a positive whole number SHALL fall back to 100 rather than being rejected.

Whether further pages exist SHALL be determined from the rows actually matching the active filters, not inferred from the current page being full. A page holding exactly the per-page row count SHALL report that no further pages exist when no further rows match. The rows used to determine this SHALL NOT be shown on the page, so a page holds at most the selected number of rows and an export of that page contains exactly the rows displayed.

#### Scenario: Paginate filtered logs

- **WHEN** user advances to the next page with filters active
- **THEN** system keeps node, search, datetime-range, and level filters and shows
  the next slice in `timestamp` descending order

#### Scenario: Empty result

- **WHEN** no rows match the active filters
- **THEN** system shows an empty state naming the active scope/filters

#### Scenario: Last page signals end of results

- **WHEN** a page returns fewer rows than the per-page limit
- **THEN** system indicates that no further pages exist and offers no way to
  advance past the last page

#### Scenario: A full page at the end of results signals no further pages

- **WHEN** a page holds exactly the per-page row count and no further rows match the
  active filters
- **THEN** system indicates that no further pages exist and offers no way to advance

#### Scenario: A full page with more rows behind it offers a next page

- **WHEN** a page holds exactly the per-page row count and further rows match the
  active filters
- **THEN** system offers a way to advance to those further rows

#### Scenario: The row used to detect further pages is not shown

- **WHEN** the system determines that further pages exist
- **THEN** the page still holds at most the selected number of rows

#### Scenario: Page size and scope are preserved when advancing

- **WHEN** user advances from a page and the active filters are unchanged
- **THEN** system keeps the per-page size and the active scope in the resulting
  page

#### Scenario: The offered page sizes are 100, 500, and 3000

- **WHEN** user views the per-page row count control
- **THEN** it offers exactly the choices 100, 500, and 3000

#### Scenario: The default page size is 100

- **WHEN** user opens the viewer with no page size specified
- **THEN** the page shows at most 100 rows and the control shows 100 as the
  active page size

#### Scenario: Selecting a page size shows that many rows

- **WHEN** user selects 500 as the per-page row count
- **THEN** the page shows at most 500 rows, and the same size stays in effect
  while advancing to the next page

#### Scenario: A page size outside the offered set is still honoured

- **WHEN** a URL carries a per-page row count that reads as a positive whole
  number but is not one of 100, 500, or 3000
- **THEN** system uses that page size rather than rejecting the request

#### Scenario: A page size above the maximum is capped

- **WHEN** a URL carries a per-page row count greater than 3000
- **THEN** the page holds at most 3000 rows

#### Scenario: An unreadable page size falls back to the default

- **WHEN** a URL carries a per-page row count that is not a positive whole
  number
- **THEN** system uses 100 and reports no error
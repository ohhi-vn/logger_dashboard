# Time Range Input Specification

## Purpose

Gives operators a fast, unambiguous way to express a datetime range when
scanning recent logs or pruning old ones, without hand-typing ISO8601 strings
and without a picker whose timezone silently disagrees with the data.

## Requirements

### Requirement: UTC datetime picker paired with the ISO8601 field

The system SHALL offer, for every datetime bound it accepts, a native
datetime picker alongside the ISO8601 text field for that bound. The picker
SHALL display UTC and SHALL write back UTC. The text field SHALL remain the
authoritative value the form submits, so a range expressed entirely through the
text fields is unaffected by the presence of a picker.

#### Scenario: Picker displays the bound in UTC

- **WHEN** a bound is set to `2026-09-01T14:30:00Z`
- **THEN** the picker for that bound shows `2026-09-01 14:30` and the text field
  shows the same instant

#### Scenario: Choosing a picker value submits that UTC instant

- **WHEN** user picks `2026-09-01 14:30` in the picker for a bound
- **THEN** the bound submitted is `2026-09-01T14:30:00Z` and the filter is
  applied as that UTC instant

#### Scenario: Picker and text field cannot disagree

- **WHEN** user types a bound directly into the text field
- **THEN** the picker for that bound reflects the typed instant, or shows
  empty when the typed value is not a valid datetime

#### Scenario: Range remains expressible without a picker

- **WHEN** a bound is set only through the text field
- **THEN** system filters by that bound exactly as before

### Requirement: Relative-range shortcuts for the viewer

The viewer SHALL offer shortcuts that select a lookback window ending at the
current time: last 10 minutes, last hour, last 6 hours, last 24 hours, last 7
days, and all time. Selecting a shortcut SHALL set both bounds to the resolved
window. Selecting all time SHALL clear both bounds.

#### Scenario: Shortcut selects a lookback window

- **WHEN** user selects "last hour"
- **THEN** the active range is the hour ending now, and the page shows a `from`
  one hour before the current time and a `to` of the current time

#### Scenario: All time clears the range

- **WHEN** user selects "all time"
- **THEN** no `from` and no `to` bound are applied

#### Scenario: Shortcut replaces any range already active

- **WHEN** a bounded range is active and user selects "last 24 hours"
- **THEN** the previous bounds are discarded and the active range is the 24
  hours ending now

#### Scenario: A manually entered bound is not silently discarded

- **WHEN** user edits a bound in a text field and submits the filter form
- **THEN** system applies the entered bound and applies no shortcut window over
  it

### Requirement: Shortcut resolution is server-side and never stale

The system SHALL resolve a selected shortcut at request time against the
server clock, so a URL that carries a shortcut always describes a window
ending now. The system SHALL record the shortcut's identity in the URL and
SHALL NOT write the resolved instants into the URL in place of it.

#### Scenario: Shortcut URL stays fresh

- **WHEN** user loads a URL carrying a shortcut some time after creating it
- **THEN** the active range is the shortcut's window ending at that load's
  current time, not the instant the URL was created

#### Scenario: Shortcut is identified in the URL

- **WHEN** a shortcut is active
- **THEN** the URL names the shortcut rather than a pair of concrete instants

#### Scenario: Resolved range is visible after resolution

- **WHEN** a shortcut is active
- **THEN** the page shows the concrete UTC `from` and `to` the system resolved
  it to

### Requirement: Unknown shortcut is rejected

The system SHALL reject a shortcut identifier it does not recognize, and SHALL
run no query and no mutation for that request.

#### Scenario: Unrecognized shortcut rejected

- **WHEN** a request carries a shortcut identifier the system does not offer
- **THEN** system rejects it with a validation error and runs no query

### Requirement: Shortcuts never perform a mutation

Selecting a shortcut SHALL only populate filter state. It SHALL NOT preview,
confirm, or execute a destructive action, and it SHALL NOT bypass any
confirmation step that applies to the surrounding operation.

#### Scenario: Shortcut on a destructive page takes no action

- **WHEN** user selects a shortcut on the prune page
- **THEN** no delete is dispatched and no confirmation step is skipped

#### Scenario: Shortcut alone is not an accepted destructive request

- **WHEN** a destructive request arrives carrying only a shortcut identifier
  and no explicit scope
- **THEN** system rejects it as it would reject a request with no scope

### Requirement: One range control serves every page that filters by time

The viewer, the analysis page, and the prune page SHALL present the same
datetime-picker and shortcut affordance for the same bound, so an operator who
has learned one page's controls finds the same controls on the others. A bound
that a page does not accept SHALL NOT offer a control for it.

#### Scenario: Controls match across pages

- **WHEN** user uses the `from` bound on the viewer, the analysis page, and the
  prune page
- **THEN** each offers the same picker and the same set of applicable
  shortcuts

# Spec Delta

## ADDED Requirements

### Requirement: Chart style selection

The Analysis page SHALL offer a chart-style control for each breakdown it charts, offering the styles that breakdown's data can represent, and SHALL keep the chosen style in the URL so a shared link reproduces the same charts. A requested style the data cannot represent SHALL fall back to one it can, and the control SHALL show the style in use. The by-node breakdown SHALL offer a chart beside its table. Choosing a style SHALL change the presentation only, never the numbers.

#### Scenario: Every charted breakdown has a style control
- **WHEN** user views the Analysis page
- **THEN** each breakdown that is charted offers a control naming the chart styles available for it

#### Scenario: The styles offered fit the data
- **WHEN** user opens a breakdown's style control
- **THEN** it offers the styles that breakdown's result can represent, and no style that would misrepresent it

#### Scenario: The chosen style travels in the URL
- **WHEN** user changes a chart style and shares the page URL
- **THEN** the shared URL reproduces the same charts, without re-choosing the style

#### Scenario: A style the data cannot represent falls back visibly
- **WHEN** the requested style cannot represent the breakdown's data
- **THEN** the chart renders in a style that can, and the control shows the style actually in use

#### Scenario: The by-node breakdown is charted
- **WHEN** user views the per-node breakdown
- **THEN** a chart of the per-node counts is offered alongside the per-node table

#### Scenario: Choosing a style changes no number
- **WHEN** user changes a chart style
- **THEN** the counts, the tables, and the disclosed analysis limit are the same as before the change

#### Scenario: Choosing a style needs no separate run action
- **WHEN** user picks a chart style
- **THEN** the chart updates without an Apply or Run action

### Requirement: Analysis keyword search semantics

The Analysis page's keyword scope SHALL match messages with the same semantics the Logs page uses: terms matched without regard to letter case, with several space-separated terms combined with AND, and a term without a wildcard matching anywhere in the message. Every breakdown — by level, volume over time, and by node — SHALL count only rows matching every term, and an empty keyword SHALL apply no message predicate.

#### Scenario: Keyword matching ignores letter case
- **WHEN** user enters `Timeout` and a row's message reads `connection timeout`
- **THEN** that row is counted in the level, volume, and node breakdowns

#### Scenario: Several keyword terms narrow every breakdown
- **WHEN** user enters `*timeout* *db*`
- **THEN** the level, volume, and node breakdowns each count only rows whose message matches both terms

#### Scenario: An empty keyword applies no message predicate
- **WHEN** user runs the analysis with an empty search value
- **THEN** the breakdowns count every row in the scope, range, and level set

#### Scenario: The handoff keyword keeps the same semantics
- **WHEN** user arrives at the Analysis page through the Logs page handoff carrying a keyword
- **THEN** the keyword is matched with the same case-insensitive, multi-term semantics as a hand-entered one

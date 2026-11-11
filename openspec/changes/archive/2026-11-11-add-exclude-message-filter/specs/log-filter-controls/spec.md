# Spec Delta

## MODIFIED Requirements

### Requirement: One filter control vocabulary across pages

The Logs, Analysis, and Prune pages SHALL present their node scope, level scope,
message search, and message exclusion through the same shared controls, drawn
from the same level vocabulary and the same known-node list together with every
node in the active scope, and SHALL mark the active selection the same way on
every page. A control learned on one page SHALL be recognizable on the others
and SHALL behave the same way there. The Prune page SHALL offer no search or
exclude control, because a prune does not filter by message.

#### Scenario: The same control set appears on every page
- **WHEN** user views the node scope, level scope, and search controls on the Logs, Analysis, and Prune pages
- **THEN** each page shows the same control for each of them, not a page-specific variant

#### Scenario: The same level vocabulary is offered everywhere
- **WHEN** user views the level control on any of the three pages
- **THEN** the same set of level options is offered as elsewhere, and the same "all levels" reset is available

#### Scenario: The same known-node list is offered everywhere
- **WHEN** user views the node scope control on any of the three pages
- **THEN** the options offered are the distinct node values known from the logs table together with every node in the active scope, and they do not depend on the rows currently on screen

#### Scenario: The active selection is marked the same way
- **WHEN** a node or level is active on any of the three pages
- **THEN** that page marks it as active in the same way the other pages do

### Requirement: The search control states the matching syntax

The message search and message exclusion controls SHALL state the syntax they
accept: `*` matches any run of characters, `?` matches a single character, a
term with no wildcard matches anywhere in the message, matching ignores letter
case, and space-separated terms are combined with AND. Every page that offers a
search or exclude control SHALL state the same syntax, and a page that cannot
filter by message SHALL offer no such control.

#### Scenario: The syntax is stated where the search is entered
- **WHEN** user views the search control
- **THEN** the control states the wildcard characters, the case-insensitivity, and the AND combination of separate terms

#### Scenario: Every page offering search states it identically
- **WHEN** user compares the search control on the Logs page and the Analysis page
- **THEN** both state the same syntax and accept the same terms

#### Scenario: A page that cannot filter by message offers no search control
- **WHEN** user views the Prune page
- **THEN** no search control is offered, because a prune does not filter by message

#### Scenario: The syntax is stated where the exclude is entered
- **WHEN** user views the exclude control
- **THEN** the control states the wildcard characters, the case-insensitivity,
  and the AND combination of separate terms

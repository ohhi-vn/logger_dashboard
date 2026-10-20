# Log Filter Controls Specification

## Purpose

Gives the Logs, Analysis, and Prune pages one vocabulary of filter controls — node scope, level scope, and message search — so the same filtering intent is expressed the same way on every page, configured per page only where the pages genuinely differ.

## Requirements

### Requirement: One filter control vocabulary across pages

The Logs, Analysis, and Prune pages SHALL present their node scope, level scope, and message search through the same shared controls, drawn from the same level vocabulary and the same known-node list together with every node in the active scope, and SHALL mark the active selection the same way on every page. A control learned on one page SHALL be recognizable on the others and SHALL behave the same way there.

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

### Requirement: Per-page selection mode

The node scope and level scope controls SHALL support a multi-select mode, in which clicking an option toggles it in or out of the active set, and a single-select mode, in which clicking an option replaces the active selection. The Logs and Analysis pages SHALL use multi-select; the Prune page SHALL use single-select. The mode SHALL be a property of the control, not of the page that renders it.

#### Scenario: Multi-select mode toggles membership
- **WHEN** user clicks a node or level option in multi-select mode
- **THEN** the option joins the active set, and clicking it again removes it, leaving the other active filters unchanged

#### Scenario: Single-select mode replaces the selection
- **WHEN** user clicks a node or level option in single-select mode
- **THEN** the option becomes the whole active selection for that filter, replacing any previous selection

#### Scenario: Single-select mode can return to the unfiltered choice
- **WHEN** user activates the "all levels" reset in single-select mode
- **THEN** the level scope is empty and no level predicate applies

#### Scenario: A single-select scope names what it targets
- **WHEN** user selects a node in single-select mode
- **THEN** that node alone is what the operation targets, and no other node is included

#### Scenario: The mode does not change the other filters
- **WHEN** user changes the node scope or the level scope in either mode
- **THEN** the remaining filters, and the range where one is offered, stay exactly as they were

### Requirement: The search control states the matching syntax

The message search control SHALL state the syntax it accepts: `*` matches any run of characters, `?` matches a single character, a term with no wildcard matches anywhere in the message, matching ignores letter case, and space-separated terms are combined with AND. Every page that offers a search control SHALL state the same syntax, and a page that cannot filter by message SHALL offer no search control.

#### Scenario: The syntax is stated where the search is entered
- **WHEN** user views the search control
- **THEN** the control states the wildcard characters, the case-insensitivity, and the AND combination of separate terms

#### Scenario: Every page offering search states it identically
- **WHEN** user compares the search control on the Logs page and the Analysis page
- **THEN** both state the same syntax and accept the same terms

#### Scenario: A page that cannot filter by message offers no search control
- **WHEN** user views the Prune page
- **THEN** no search control is offered, because a prune does not filter by message

### Requirement: Filter controls show the values in effect

The filter controls SHALL show the values the system actually applied, including the concrete instants a relative shortcut resolved to, and SHALL show the submitted values when the request was rejected, so the controls on screen and the results on screen always describe the same filter set.

#### Scenario: The controls show the resolved shortcut instants
- **WHEN** a relative shortcut is active
- **THEN** the range controls show the UTC instants the shortcut resolved to, not the shortcut's label alone

#### Scenario: A rejected request shows what was submitted
- **WHEN** the system rejects a filter
- **THEN** the controls show the values that were submitted, alongside the validation error naming the rejected field

### Requirement: The node scope control always offers the active scope

The node scope control SHALL offer every node in the active scope, whether or not that node is among the known node values, so that a node in scope is always visible and can always be removed through the control.

#### Scenario: An active node outside the known node list is still offered
- **WHEN** the active scope names a node that is not among the known node values
- **THEN** the node scope control still offers that node as an option, marked as in scope

#### Scenario: An active node is removable through the control
- **WHEN** user clicks an offered node that is in the active scope
- **THEN** the node leaves the active scope, on every page that offers the control

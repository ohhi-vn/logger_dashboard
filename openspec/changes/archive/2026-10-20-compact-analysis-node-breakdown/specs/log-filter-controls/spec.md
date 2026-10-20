# Spec Delta

## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: The node scope control always offers the active scope

The node scope control SHALL offer every node in the active scope, whether or not that node is among the known node values, so that a node in scope is always visible and can always be removed through the control.

#### Scenario: An active node outside the known node list is still offered
- **WHEN** the active scope names a node that is not among the known node values
- **THEN** the node scope control still offers that node as an option, marked as in scope

#### Scenario: An active node is removable through the control
- **WHEN** user clicks an offered node that is in the active scope
- **THEN** the node leaves the active scope, on every page that offers the control

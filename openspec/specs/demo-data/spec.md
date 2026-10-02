# Demo Data Specification

## Purpose

Provides reproducible synthetic logs in the shared ClickHouse table so developers and demos can exercise browsing, analysis, and pruning without real traffic.

## Requirements

### Requirement: Multi-level log generation

The system SHALL generate log rows across `debug`, `info`, `warning`, and `error` levels with realistic per-level messages, caller attributes, and metadata.

#### Scenario: Default level mix
- **WHEN** operator runs the generator with defaults
- **THEN** the system creates rows covering all four levels with `message`, `module`, `function`, `file`, `line`, and stringified `metadata` populated

#### Scenario: Explicit level filter
- **WHEN** operator passes `--levels error,warning`
- **THEN** the system creates only rows whose `level` is `error` or `warning`

#### Scenario: Invalid level rejected
- **WHEN** operator passes an unknown level such as `--levels verbose`
- **THEN** the system rejects the run with a validation error and writes no rows

### Requirement: Multi-node log generation

The system SHALL generate rows across one or more named nodes with a selectable distribution strategy.

#### Scenario: Multiple nodes round-robin
- **WHEN** operator passes `--nodes web@10.0.0.1,worker@10.0.0.2` with round-robin distribution
- **THEN** the system assigns `node` values cycling evenly across the listed nodes

#### Scenario: Random node distribution
- **WHEN** operator selects random node distribution
- **THEN** the system assigns each row a `node` sampled from the listed nodes

#### Scenario: Single node default
- **WHEN** operator omits `--nodes`
- **THEN** the system generates rows for a single sensible default node

### Requirement: Date-range timestamp spread

The system SHALL spread generated `timestamp` values across an explicit UTC date range with inclusive bounds.

#### Scenario: Explicit range
- **WHEN** operator passes `--from 2026-09-01T00:00:00Z --to 2026-09-08T00:00:00Z`
- **THEN** the system creates rows whose `timestamp` values fall within that range

#### Scenario: Default recent range
- **WHEN** operator omits `--from`/`--to`
- **THEN** the system spreads timestamps across the last 7 days ending at run time

#### Scenario: Invalid range rejected
- **WHEN** operator passes `from` after `to` or unparseable datetimes
- **THEN** the system rejects the run with a validation error and writes no rows

### Requirement: Volume and reproducibility controls

The system SHALL support explicit volume controls and deterministic re-runs via seed and presets.

#### Scenario: Exact count
- **WHEN** operator passes `--count 5000`
- **THEN** the system creates exactly 5000 rows

#### Scenario: Seeded repeatability
- **WHEN** operator runs twice with the same `--seed` and identical options
- **THEN** the system produces the same sequence of levels, nodes, timestamps, and messages

#### Scenario: Preset sizes
- **WHEN** operator passes `--preset small|medium|burst`
- **THEN** the system applies a documented row-count and level-mix preset usable for quick demos versus load checks

### Requirement: Safe non-destructive generation

The system SHALL only insert rows, never delete, and SHALL guard production use plus support dry-run planning.

#### Scenario: Inserts only
- **WHEN** the generator completes
- **THEN** pre-existing rows remain untouched and only new rows are added

#### Scenario: Dry run writes nothing
- **WHEN** operator passes `--dry-run`
- **THEN** the system prints planned counts per level and per node and writes zero rows

#### Scenario: Production guard
- **WHEN** operator runs in `prod` without `--allow-prod`
- **THEN** the system aborts with an error and writes no rows

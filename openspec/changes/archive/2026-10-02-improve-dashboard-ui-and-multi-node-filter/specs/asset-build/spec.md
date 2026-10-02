# Spec Delta

## Purpose

Ensures developers can build the dashboard's CSS and JS assets from the repository, including on macOS versions that reject the downloaded Tailwind standalone binary's code signature.

## ADDED Requirements

### Requirement: Tailwind CLI runs after install on macOS

The system SHALL ensure the downloaded Tailwind CLI executable is ad-hoc code-signed on macOS before any asset build invokes it, so the OS does not terminate it with an invalid-code-signature error. On non-macOS platforms, or when no downloaded binary is present, the signing step SHALL be a no-op.

#### Scenario: Asset build completes on macOS

- **WHEN** a developer runs `mix assets.build` on macOS with the downloaded Tailwind binary present
- **THEN** the Tailwind CSS build runs to completion and the command exits successfully

#### Scenario: Signing is idempotent

- **WHEN** the Tailwind binary is already ad-hoc signed
- **THEN** re-running the signing step leaves it runnable and the asset build still succeeds

#### Scenario: Non-macOS platforms are unaffected

- **WHEN** the asset build runs on a non-macOS platform
- **THEN** no code-signing step is attempted

#### Scenario: Missing binary is tolerated

- **WHEN** the signing step runs before the Tailwind binary has been downloaded
- **THEN** it is a no-op and does not fail the build setup

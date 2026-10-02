# Design

## Context

See `proposal.md` for motivation. The current state that shapes the approach:

- `LoggerDashboard.Logs.Filter` is the single validated filter representation. It carries `node: String.t() | nil` and emits `node = ?` through `Filter.predicates/1`. Three consumers share it: `LogRead` (raw SQL read), `Prune` (raw `ALTER TABLE ... DELETE`), and `Analysis` (AshDyan, which converts a filter map via `Ash.Filter.parse/2`).
- `Layouts.app/1` is the stock Phoenix header linking to phoenixframework.org; pages do not link to each other, and `/` renders the boilerplate `home.html.heex`.
- `mix assets.build` downloads Tailwind 4.3.0 to `_build/tailwind-macos-arm64-4.3.0`. On this macOS the binary is killed with `SIGKILL (Code Signature Invalid)`; ad-hoc re-signing it (`codesign --force --sign -`) makes it run. The `:tailwind` Hex package supports a `:path` override and a per-profile `args`/`cd`, but only downloads the official binary by default.

## Goals / Non-Goals

**Goals:**

- Multi-node node scope for the Logs viewer and the Analysis page, as bound parameters.
- One shared, persistent navigation shell plus a dashboard homepage.
- `mix assets.build` / `assets.setup` / `assets.deploy` succeed on macOS without changing the Tailwind version or adding an npm toolchain.
- Keep the change to the shared `Filter` representation small enough that pruning's safety model is preserved verbatim.

**Non-Goals:**

- Multi-node pruning (explicitly excluded; prune stays single-node or whole-system).
- Changing the Tailwind version, using `config :tailwind, :path`, or moving to npm-managed Tailwind.
- Database migrations or new ClickHouse columns.
- Authentication, authorization, or tenancy changes.
- Redesigning the AshDyan chart pipeline.

## Decisions

### D1. Node scope becomes a list on the shared `Filter`

Replace `node: String.t() | nil` with `nodes: [String.t()]`, where `[]` means "all nodes". All consumers keep using one `Filter`.

- Rationale: one representation and one predicate builder; no parallel parse logic.
- Alternatives: keep both `node` and `nodes` (two representations drift); a separate viewer/analysis filter type (duplicates parse and predicate rules). Rejected.
- Consequence: every `filter.node` call site and test is updated in lockstep; the compiler finds them.

### D2. Emit `node IN (?, ...)` from `Filter.predicates/1`

When `nodes` is non-empty emit `node IN (?, ?, ...)` with one bound parameter per node; otherwise emit no node clause (so an empty filter still yields `1 = 1`). Every value is bound.

- Rationale: ClickHouse handles `IN` natively; one clause covers one-or-many nodes.
- Alternative: an `OR` chain of `node = ?` (longer SQL, identical result). Rejected.
- Note: a single node now produces `node IN (?)` rather than `node = ?`; behavior is identical.

### D3. Parse the node filter as a comma-separated list

`parse_nodes/1` splits on `,`, trims each entry, drops blanks, and de-duplicates; an input that reduces to nothing maps to `[]`. The filter value stays a single `node` query parameter whose value is a comma-joined string, so URLs stay shareable.

- Rationale: no new query to enumerate distinct nodes, and node names not yet present can still be targeted.
- Trade-off: a literal comma in a node name would split; node values are `name@host`, so this is acceptable.

### D4. Prune keeps its single-node/all-nodes safety model

`Prune.parse/1` still accepts scope `node` or `all`. For scope `node` it must resolve to exactly one node; a value that parses to more than one node is rejected with a validation error. It then builds the shared `Filter` with `nodes: [value]`. `Prune.describe/2` and `Prune.run/2` read `filter.nodes`.

- Rationale: the confirmation prompt states the resolved scope; silently widening a confirmed single-node prune to several nodes would breach that contract.
- Alternative: multi-node prune with its own confirmation (out of scope by decision).

### D5. Analysis multi-node via Ash `in`

`Analysis.dyan_filters/1` emits `%{node: %{in: nodes}}` when `nodes` is non-empty. Ash 3.33 exposes the `:in` operator, `AshClickhouse`'s `build_comparison(:in, ...)` builds `IN`, and `allow_filters_on([:node, ...])` already whitelists the field. A `:clickhouse`-tagged test asserts multi-node aggregation returns both nodes' rows.

- Risk fallback: if AshDyan/Ash rejects the `in` shape, compute multi-node analysis through the raw-SQL path already sanctioned for text search. This is only a fallback; the capability spec does not change.

### D6. Shared shell with an `active` page marker

Extend `Layouts.app/1` with an `active` attribute (`:home | :logs | :analysis | :prune | nil`). It renders a top navigation bar (`navigate` links to `/`, `/logs`, `/analysis`, `/prune`), marks the active link with `aria-current="page"`, and keeps the theme toggle and flash group inside the shell. LiveViews pass `active` when rendering `<Layouts.app>`; the controller home template renders inside `<Layouts.app active={:home}>`.

- Rationale: one shell, no duplicated headers; the router already exposes all routes, so no route changes.
- Alternatives: a sidebar (more chrome than the app needs); a LiveView homepage (unnecessary for static links). Rejected.

### D7. Ad-hoc sign the Tailwind binary before running it

Add `Mix.Tasks.LoggerDashboard.SignTailwind`: on `:darwin`, if `Tailwind.bin_path()` exists and `codesign` is on `PATH`, run `codesign --force --sign - <path>`. It is a no-op elsewhere or when the binary is absent, and safe to re-run.

Wire it so every entry point signs after install and before execution:

- `assets.setup`: `tailwind.install --if-missing` → `logger_dashboard.sign_tailwind`
- `assets.build`: `compile` → `tailwind.install --if-missing` → `logger_dashboard.sign_tailwind` → `tailwind logger_dashboard` → `esbuild logger_dashboard`
- `assets.deploy`: `tailwind.install --if-missing` → `logger_dashboard.sign_tailwind` → `tailwind ... --minify` → `esbuild ... --minify` → `phx.digest`
- `config/dev.exs` watcher: replace `{Tailwind, :install_and_run, [...]}` with a thin `LoggerDashboard.Tailwind.install_and_run/2` that signs then delegates, so `mix phx.server` is covered too.

The explicit `tailwind.install --if-missing` before the run matters: `mix tailwind` only installs when the file is missing, so signing must happen between install and run. Because `install_and_run` sees the file already present, it skips re-downloading the freshly signed binary.

- Rationale: repairs build output locally; no dependency or version change.
- Alternatives: `config :tailwind, :path` to an npm-managed CLI (adds a Node toolchain and a second package manager); pinning another Tailwind release (unverified, likely the same linker-signed binary). Rejected.

## Risks / Trade-offs

- [`Filter` field rename ripples through read/prune/analysis and their tests] → update all call sites in one change; compile-time errors plus `mix precommit` catch misses. No external API is affected.
- [AshDyan may reject the `in` filter shape] → covered by an explicit multi-node analysis test; fallback is raw aggregate SQL (D5).
- [Signing changes a build artifact] → it is regenerated by `tailwind.install`, never committed, and re-running is idempotent.
- [`codesign`/Apple CLT absent] → the step no-ops; behavior then matches today (build still fails on affected machines, but the step does not introduce a new failure).
- [Comma in a node name] → node values are `name@host`; splitting is acceptable (D3).

## Migration Plan

Code-only; no database migration. Release flow: run `mix assets.build` (or `assets.deploy`) before building a release. Rollback: revert the commit; assets rebuild as before. The `Filter` field change is internal and compile-time checked, so no runtime data migration is needed.

## Open Questions

None blocking. The AshDyan `in` pushdown is validated by a test during implementation rather than deferred.

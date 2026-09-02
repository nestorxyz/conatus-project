# Conatus Implementation Results

## 2026-09-01 — M1-03 durable Codex binding and writer lease

**Status:** complete through disposable local SQLite verification. No Codex
process, provider credential, provider account, real provider reference, or
persistent Codex task was used.

### Delivered

- ADR 0014 fixes local ownership: Core and clients know Conatus Workspace, Task,
  and binding IDs; only the Mac Gateway journal stores canonical paths and
  provider task references.
- Private SQLite journal using foreign keys, WAL mode, full synchronous
  durability, schema-version refusal, and owner-only permissions for the
  database and journal sidecars.
- Canonical existing-directory registration with symlink resolution, no silent
  rebind, no duplicate path ownership, and availability revalidation before
  local use.
- One opaque binding per Conatus Task, local-only provider references, immutable
  idempotency receipts, and redacted unbound/create-pending/resume-ready restart
  reconciliation.
- Per-Task writer leases using immediate transactions and durable increasing
  fence tokens; expired takeover makes every older holder stale.

### Verification

- `pnpm check:m1-03` passed five local-journal tests plus the nine existing
  Gateway and Codex-contract tests, with 14 tests and zero failures.
- Two independent journal connections proved one live writer, expiry takeover,
  increasing fences, release without resetting the fence, and stale-writer
  rejection.
- Fresh connections recovered the same pending-create and resume-ready states;
  repeated semantic requests returned the original receipt and changed
  fingerprints failed closed.
- Encoded public results contained no canonical path, provider task reference,
  or provider field. The database, WAL, and shared-memory files were mode 0600.
- A newer schema version was rejected and remained unchanged; a removed
  registered directory failed availability revalidation.
- `pnpm check:f03` passed the complete TypeScript, Swift Gateway, Codex-contract,
  and disposable PostgreSQL foundation regression.
- Repository formatting, shell lint, negative quality fixtures, lockfile,
  secret, AGPL, dependency-license, and production dependency audit gates
  passed with no known vulnerabilities.

### Audit and next step

- The AI-code audit narrowed SQL projections, separated the SQLite wrapper from
  journal policy, added typed corruption/schema failures, and closed silent
  schema-downgrade and stale-workspace-path cases before completion.
- M1-04 is next: an explicitly approved, bounded, account-backed read-only Codex
  create/resume lifecycle through this journal. It must prove exact identity
  across Gateway restart without sending a mutating turn or creating a
  duplicate provider task.
- Hosted GitHub CI remains the pre-merge, external-contribution, and release
  gate recorded under F03.

## 2026-09-01 — M1-02 registered workspace and portfolio projection

**Status:** complete through disposable PostgreSQL verification under Node
24.19.0 and pnpm 10.29.2. No production database, authentication provider,
workspace path, Codex process, provider account, or persistent Codex task was
used.

### Delivered

- ADR 0013 defines Conatus-owned named routing: stable account-scoped IDs,
  Workspace handles, separate aliases, and typed deterministic ambiguity rather
  than first-match guessing.
- PostgreSQL migration for Workspace, Product, Project, and Task aliases plus
  active Task blockers and verified/unverified/failed Task result summaries.
- Core resolution by Conatus ID, primary name, or normalized alias, with an
  optional parent Project/Product context for explicit disambiguation.
- Repeatable-read command-center projection containing Workspaces, Products,
  Projects, Tasks, active blockers, and at most five recent results per Task.
- Atomic aggregate-version, DomainEvent, and OutboxRecord updates for alias,
  blocker, and result mutations.
- Serialized alias insertion on the owning aggregate, so concurrent duplicate
  alias requests produce one durable alias and one transition.
- Ordered migration discovery that skips already-applied versions.

### Verification

- `pnpm check:m1-02` passed all 16 Core tests against fresh PostgreSQL 18 and
  removed its disposable container, network, and volume afterward.
- Primary names, diacritic/case normalization, aliases, Conatus IDs,
  deterministic ambiguity, and parent-context disambiguation passed.
- Cross-account resolution, alias mutation, blocker mutation, and projection
  reads exposed no owning-account state.
- A fresh Core connection returned the exact same projection; its serialized
  payload contained no absolute path, `cwd`, provider field, or thread ID.
- Events and outbox records remained one-to-one after all M1-02 mutations.
- `pnpm check:f03` passed the complete TypeScript, Swift Gateway, Codex contract,
  and disposable PostgreSQL foundation regression.
- Repository formatting, shell lint, negative quality fixtures, lockfile,
  secret, AGPL, dependency-license, and production dependency audit gates
  passed with no known vulnerabilities.

### Limitations and next step

- M1-02 is an internal Core capability. No HTTP endpoint or Mac command-center
  screen exposes the portfolio yet.
- Core deliberately has no local filesystem path mapping. M1-03 adds the
  Gateway-owned workspace binding, local receipts, writer lease, fencing, and
  idempotent Codex create/resume preparation.
- Live account-backed Codex execution remains M1-04 and still requires explicit
  approval before it is attempted.
- Hosted GitHub CI remains the pre-merge, external-contribution, and release
  gate recorded under F03.

## 2026-09-01 — M1-01 Codex App Server compatibility pin

**Status:** complete through local contract generation and request-vector
verification. No Codex provider process was started, no account-backed request
was made, and no persistent Codex task was created.

### Delivered

- ADR 0012 fixes the first M1 provider boundary to local stdio JSONL and a
  narrow, non-experimental App Server surface.
- Exact development candidate pin for `codex-cli 0.150.1` and SHA-256 digest
  `8cdccfc35582696d7141e7f916e0d5a664ab5b5e90b732f104284d2507f369f8`
  of its generated non-experimental v2 schema bundle.
- Reproducible compatibility check that generates schema into a temporary
  directory and rejects version, digest, or allowlisted-method drift.
- Swift request types for stable initialization, thread start/read/resume, and
  turn start. Creation and turns can express only approval policy `never` and a
  read-only sandbox with network access disabled.
- Input rejection for relative or non-normalized workspace paths, empty
  provider identifiers, and empty command text.

### Verification

- `pnpm check:m1-01` passed under Node 24.19.0 and pnpm 10.29.2.
- Five new Codex contract tests and the four existing Gateway lifecycle tests
  passed with zero failures.
- `pnpm check:f03` passed the complete prior foundation regression, including
  ten disposable PostgreSQL tests and all Swift/TypeScript contracts.
- Repository formatting, shell lint, negative quality fixtures, lockfile,
  secret, AGPL, and dependency-license gates passed.
- `pnpm audit --prod` reported no known vulnerabilities.

### Limitations and next step

- The pin proves compatibility with one locally installed development
  candidate; it is not a signed distribution dependency or evidence of
  commercial entitlement.
- Hosted GitHub CI remains blocked by the previously recorded account billing
  lock and is still required before merge, external contribution acceptance,
  or release.
- M1-02 is next: registered account-scoped workspace handles and the persistent
  Products, Projects, Tasks, blockers, and results projection. The first real
  account-backed read-only Codex lifecycle remains M1-04 and requires explicit
  approval at that stage.

## 2026-09-01 — F03 CI and local supervision boundary

**Status:** complete for internal product development through reproducible local
verification on Node 24.19.0 with pnpm 10.29.2, macOS Swift, and disposable
PostgreSQL. Hosted CI remains blocked before runner allocation by an account
billing lock and is required before merge, external contributions, or release.

### Delivered

- ADR 0011 fixes the shipped Mac Gateway/Machine Bridge direction in Swift;
  Node is development orchestration only and is not part of the Mac bundle.
- Swift Gateway helper supervision with a narrow readiness signal, bounded
  readiness timeout, visible restart count, bounded restart exhaustion, and an
  explicit live helper session lifecycle.
- A fake provider that fails once, then remains alive after readiness while
  emitting deliberately private-looking output that cannot cross the diagnostic
  boundary.
- Allowlisted Gateway health diagnostics with no credential, transcript,
  workspace path, raw helper output, or private provider reference.
- Core startup rejection of development-auth bypass in production mode and a
  standalone PostgreSQL migration command.
- `check:f03` orchestration across F01 contracts, F02 disposable PostgreSQL
  invariants, and F03 Gateway lifecycle tests.
- GitHub Actions jobs for locked Node 24 Linux domain checks and macOS Swift/TS
  foundation checks, with read-only repository permissions and job timeouts.

### Local verification

- `pnpm check:f03` passed under Node 24.19.0 and pnpm 10.29.2.
- F01 passed TypeScript builds/tests and two Swift contract vectors.
- F02 passed ten tests against disposable PostgreSQL 18, then removed its test
  container, network, and volume.
- F03 passed four Swift lifecycle tests: release-auth rejection, fail-once
  restart and redaction, silent-helper timeout, and bounded restart exhaustion.
- Repository formatting, shell lint, negative quality fixtures, lockfile,
  secret, AGPL, and dependency-license gates passed.
- `pnpm audit --prod` reported no known vulnerabilities.

### Remote verification blocker

- Push commit `a3f2cbf35609e905d2ead082ece5e8f9d20e9250` triggered
  [GitHub Actions run 33567797351](https://github.com/nestorxyz/conatus-project/actions/runs/33567797351).
- GitHub created all three jobs but assigned no runner and executed zero steps.
  Each public check annotation says: `The job was not started because your
  account is locked due to a billing issue.`
- Restoring GitHub Actions billing and rerunning this workflow remains a
  pre-merge, external-contribution, and release gate. It no longer blocks
  internal product development because equivalent local Node 24/macOS/
  PostgreSQL evidence is recorded above.

### Still intentionally absent

- Live Codex/App Server execution, provider credentials, signing, installation,
  login-item behavior, sleep/wake recovery, cloud deployment, and production
  migrations remain later tickets.

### Next step

Start M1's real Mac product foundation. Resolve the GitHub account billing lock
and record a successful hosted run before merging, accepting an external
contribution, or preparing a release.

## 2026-09-01 — F02 durable domain kernel and failure tests

**Status:** implemented and verified against disposable PostgreSQL 18 on the
available Mac toolchains. No production database, account, provider, or customer
data was created.

### Delivered

- ADR 0010 defines Account as the isolation root and preserves separate
  portfolio, command, delivery, execution, event, idempotency, and outbox
  boundaries.
- PostgreSQL migration for Account, Principal, Device, Machine, Workspace,
  Product, Project, Task, Command, Delivery, ExecutionAttempt, DomainEvent,
  IdempotencyRecord, and OutboxRecord.
- Composite account-scoped primary and foreign keys prevent child records from
  crossing account ownership through joins.
- UUIDv7 identity generation, optimistic aggregate versions, canonical request
  fingerprints, scoped idempotency, and duplicate execution admission.
- Atomic transaction helper that commits state, append-only events, and pending
  outbox work together.
- Disposable local PostgreSQL verification runner that removes its container,
  network, and test-only volume after every run.

### Verification

- `pnpm check:f02`: eight tests passed against a fresh PostgreSQL 18 database.
- Cross-account Task reads, renames, and execution admission were rejected
  without changing the owning account.
- Matching idempotent command replay returned the original Command; a changed
  request fingerprint was rejected.
- Two concurrent execution admissions resolved to one Delivery and one
  ExecutionAttempt.
- Two concurrent Task updates with the same expected version produced exactly
  one winner and one typed stale-version failure.
- An injected failure after aggregate writes but before event creation rolled
  state, events, idempotency, and outbox back together.
- Events and outbox records remained one-to-one and survived a fresh database
  connection with the same Task version and pending work.
- TypeScript build, F01 Swift/TypeScript contract checks, repository format,
  shell lint, negative quality fixtures, lockfile, secret, AGPL, dependency
  license, Compose validation, SBOM generation, and production dependency audit
  passed. The audit reported no known vulnerabilities.

### Verification limitations

- The repository-required `make bootstrap` still stops in the preserved
  Android/Rust component because `cargo` is not installed. No global Rust
  toolchain was installed implicitly.
- Node 24 LTS parity remains unverified locally; checks ran on Node 22.17.1 with
  an explicit engine warning.
- Authentication, policy evaluation, leases/fencing, approvals, Results and
  Verification, projections, provider adapters, deployment, and production
  migrations remain later work.

### Next ticket

F03 adds reproducible CI and local supervision for the Mac, Core, migrations,
and Gateway boundary without production credentials or a public service bind.

## 2026-09-01 — F01 Mac/Core/contracts foundation

**Status:** implemented and verified on the available Mac toolchains. Production
Node.js 24 verification remains open because this Mac currently provides Node
22.17.1. The manifest reports the mismatch instead of claiming parity.

### Delivered

- ADR 0009 and governing-document amendments make the complete Mac-first,
  voice-first product the current launch direction while preserving prior
  Android/Rust/crypto/terminal evidence.
- Native SwiftUI Mac development shell and reproducible ignored
  `build/Conatus.app` bundle.
- Strict TypeScript/Fastify Executive Core with a loopback-default health route.
- Canonical JSON Schema, valid/invalid vectors, and independent Swift/TypeScript
  validators.
- Reserved local Mac Bridge/Gateway boundary with no live executor.
- Opt-in, loopback-only PostgreSQL configuration for later durable-kernel work.
- Pinned pnpm workspace/lockfile and component ownership/build boundaries.
- Repository format and lock checks now exclude generated pnpm/Swift output.

### Verification

- `pnpm check:f01`: passed.
- TypeScript strict builds: passed.
- Tests: two TypeScript contract cases, one Core health case, and two Swift
  contract cases passed.
- `pnpm mac:app`: produced the local development application bundle.
- A live loopback request returned
  `{"schemaVersion":1,"component":"core","state":"ready","version":"0.1.0-dev"}`.
- Repository format, shell lint, quality-gate fixtures, lockfile, secret,
  AGPL/licensing, dependency-license, component-boundary, and SBOM checks passed.
- `pnpm audit --prod`: no known vulnerabilities after upgrading Fastify from
  5.6.0 to patched 5.8.5. The earlier pin had two high-severity validation-bypass
  advisories and was not retained.

### Verification limitations

- `make ci` cannot complete on this Mac because the preserved Android/Rust
  bootstrap requires `cargo`, which is not installed. No global Rust toolchain
  was installed implicitly.
- Node 24 LTS parity remains unverified locally; the current checks ran on Node
  22.17.1 with an explicit engine warning.
- Provider accounts, live Codex execution, PostgreSQL startup, deployment,
  signing, installation, microphone capture, and managed voice were not used.

### Next ticket

F02 adds the minimum durable Account, Device/Machine, Workspace,
Product/Project, Task, Command, Delivery, ExecutionAttempt, event, and outbox
boundaries needed by M1, with transaction, isolation, idempotency, stale-version,
restart, and verification tests.

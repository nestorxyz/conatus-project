# Conatus Implementation Results

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

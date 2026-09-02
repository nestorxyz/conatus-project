# Conatus Implementation Results

## 2026-09-02 — M2-02a local activated-audio kernel

**Status:** complete through deterministic native audio-kernel verification. No
microphone permission, audio engine, personal recording, model asset, Apple
Speech API, filesystem audio write, provider credential, or network call was
used.

### Delivered

- ADR 0018 selects Apple Sound Analysis with a Conatus-owned custom Core ML wake
  model for M2-02b. It rejects openWakeWord's noncommercial pretrained weights
  and any other model without explicit redistribution rights and provenance.
- A bounded mono-frame rolling buffer with strict sample-rate, continuity,
  finite-sample, range, and capacity validation. Storage compacts periodically
  rather than shifting the full window for every audio chunk.
- Activated-turn capture creates a separate bounded buffer beginning exactly at
  the accepted local wake range. Earlier ambient samples are not included, and
  overflow is cut at the configured maximum instead of silently displacing the
  activation boundary.
- A wake-score gate with threshold, consecutive evidence, overlap-aware ordering,
  replay rejection, gap reset, and cooldown. A successful activation emits
  audible and visible feedback actions immediately.
- Local energy turn-end detection that requires post-activation speech, rejects
  sample-rate or frame discontinuity, prefers a proven earlier silence boundary,
  and enforces a maximum duration.
- Transcript-free diagnostics and a `pnpm check:m2-02a` boundary gate that also
  rejects accidental microphone, network, Apple Speech, or model-asset coupling.

### Verification

- `pnpm check:m2-02a` passed under Node 24.19.0 and pnpm 10.29.2.
- Eleven local-audio tests and the twelve existing native contract/lifecycle
  tests passed, for twenty-three XCTest tests plus four Swift Testing command-center
  regressions.
- The AI-code audit separated pre-wake and activated-turn storage, removed
  repeated full-buffer shifts, rejected replayed/gapped classifier windows and
  sample-rate drift, and preserved an earlier silence end when a chunk also
  crosses the maximum duration.

### Limitations and next step

- This kernel does not yet hear the user. M2-02b is next: create the
  provenance-complete `Hey Conatus` model, add native microphone/Sound Analysis
  adapters and the privacy usage description, then run explicitly approved live
  same-sentence, false-wake, accent, sleep/wake, and audio-route tests.
- No existing third-party pretrained wake model is approved for the bundle.
- The preserved broad bootstrap still requires the legacy Android Rust
  toolchain, which is not installed. No global toolchain was installed.

## 2026-09-02 — M2-01 managed voice lifecycle contract

**Status:** complete through deterministic local contracts and native lifecycle
tests. No microphone permission, audio capture, Apple Speech API, network call,
provider credential, voice quota, or account-backed transcription was used.

### Delivered

- ADR 0017 and the governing product, technical, security, and backlog documents
  define the literal hands-free interaction: say `Hey Conatus` and continue in
  the same utterance, receive immediate audible/visible feedback, use
  account-managed cloud transcription, speak status, continue with follow-ups,
  and interrupt output through barge-in.
- A strict transcript-free TypeScript/Swift public status contract for `off`,
  `armed`, `acknowledging`, `capturing`, `transcribing`, `routing`, `working`,
  `speaking`, `recovering`, and `blocked`. Private and unknown fields, unknown
  states, and contradictory recovery projections fail closed.
- A provider-neutral native `ManagedVoiceSession` state machine. Partial events
  cannot dispatch, one non-empty final transcript per active Voice Turn ID
  produces one internal routing action, and duplicate final events are ignored.
- Explicit follow-up, barge-in, cancellation, network recovery, blocked/reset,
  and invalid-transition behavior without microphone or provider plumbing.
- A single `pnpm check:m2-01` gate for the cross-language contract and complete
  native Mac lifecycle regression.

### Verification

- `pnpm check:m2-01` passed under Node 24.19.0 and pnpm 10.29.2.
- Nine TypeScript contract tests and twelve XCTest tests passed. The native set
  includes eight voice-lifecycle tests plus existing Mac contract and command
  center regressions.
- Repository formatting, shell lint, negative quality fixtures, lockfile,
  secret, AGPL, and dependency-license checks passed.
- The AI-code audit replaced an unbounded historical Voice Turn ID set with one
  active routed ID, retained explicit enum decisions instead of boolean modes,
  and aligned semantic recovery validation across Swift and TypeScript.

### Limitations and next step

- This ticket defines behavior but does not yet listen. The next dependency-
  unblocked ticket is M2-02: local wake detection, same-utterance pre-roll and
  turn capture, microphone/audio-route handling, and immediate feedback using a
  wake model whose code and weights permit open-source commercial distribution.
- M2-03 remains responsible for account grants and quota; M2-04 for the Realtime
  transcription adapter and separately approved live validation; M2-05 for the
  integrated native conversation.
- The preserved broad bootstrap still requires the legacy Android Rust
  toolchain, which is not installed. No global toolchain was installed.

## 2026-09-02 — M1-05 native Mac command center integration

**Status:** complete through local, disposable M1 acceptance. No production
service or database was changed, and no additional account-backed Codex task or
turn was created.

### Delivered

- ADR 0016 defines an authenticated, loopback-only Core command-center route.
  Identity derives the account server-side; the request cannot select tenancy
  and the response omits account identity.
- A strict shared TypeScript/Swift command-center contract for Workspaces,
  Products, Projects, Tasks, aliases, blockers, recent results, and observation
  freshness. Unknown or private fields fail closed.
- Native SwiftUI navigation with first-view tasks and explicit loading, fresh,
  empty, stale, unconfigured, unauthorized, unavailable, and malformed states.
  The last valid portfolio remains visible but marked stale after refresh loss.
- An ID-only Task activation protocol. The Mac UI passes only Conatus Workspace
  and Task IDs; a fake-only Gateway adapter returns redacted created/resumed
  evidence and never exposes provider identity or filesystem paths.
- A single `pnpm check:m1-05` gate covering disposable PostgreSQL, Core,
  contracts, Gateway fake lifecycle, native state tests, and `.app` creation.
- PostgreSQL migrations now serialize with an advisory lock after the new
  parallel integration test exposed a real concurrent-startup race.

### Verification

- `pnpm check:m1-05` passed under Node 24.19.0 and pnpm 10.29.2.
- Five TypeScript contract tests and 21 Core tests passed against disposable
  PostgreSQL 18. The route rejected non-loopback and unauthenticated requests,
  ignored client account selection, hid reader errors, and returned no private
  account, path, or provider field.
- Twenty-two Gateway tests passed with two approval-gated live tests skipped.
  The M1-05 fake activation created once, resumed the same binding, and kept
  fake `thread/start` and `turn/start` counts at one after retry.
- Six native Mac contract/state tests passed, including cross-language vectors,
  selection preservation, stale fallback, honest first-load failures, and
  ID-only activation.
- `pnpm mac:app` built the unsigned local
  `build/Conatus.app` development bundle.
- The disposable database container, network, and volume were removed after
  the gate.
- Repository format, shell lint, negative quality fixtures, lockfile, secret,
  AGPL, and dependency-license checks passed. The broader preserved bootstrap
  still stops in the legacy Android native-core check because `cargo` is not
  installed; no global Rust toolchain was installed implicitly.

### Audit and next step

- The code/frontend audit aligned strict Swift and TypeScript contract shapes,
  added a request timeout, separated unconfigured from unauthorized UI, exposed
  tasks on first view, and hardened concurrent migration locking.
- M1 is locally complete, but hosted GitHub Actions remains blocked by the
  recorded account billing lock and is still required before merge, external
  contributions, or release.
- M2 is next. Before implementation it needs dependency-ordered tickets for
  account-managed cloud transcription, local wake detection, activated
  conversation, interruption, audio feedback, and privacy/cost controls. The
  local macOS transcript is not the intended command-transcription path.

## 2026-09-02 — M1-04 bounded account-backed read-only lifecycle

**Status:** complete through one explicitly approved account-backed Codex task
and exactly one read-only turn. The durable task remains in the signed-in Codex
account; no deletion or archival was authorized.

### Delivered

- ADR 0015 fixes the live-validation boundary to local stdio App Server, one
  exact prompt, approval policy `never`, a read-only sandbox, disabled network,
  and rejection of tool-, command-, or file-change-shaped turn items.
- A bounded Swift App Server client for initialize, thread start/read/resume,
  turn start, authoritative completion parsing, redacted typed failures,
  response-size limits, timeouts, and owned-child shutdown.
- Gateway journal schema v2 with fenced turn receipts. The exact request is
  durably prepared before dispatch and the provider turn plus exact-response
  fingerprints commit only after successful completion.
- Fail-closed recovery: an uncertain create or turn dispatch is never retried
  automatically. A committed full retry reuses the same binding and submits no
  additional task or turn.
- A stateful fake App Server that rejects prompt or structural-policy drift and
  records thread and turn counts across process restarts.

### Verification

- `pnpm check:gateway` passed 21 Swift tests with zero failures; the two
  approval-gated live tests skipped during synthetic validation. The fake
  provider observed one `thread/start` and one `turn/start` after a complete
  validator retry.
- The explicitly approved first `pnpm check:m1-04:live` passed both live tests
  in 5.489 seconds against the pinned `codex-cli 0.150.1`. The final reply was
  exactly `CONATUS_M1_04_READY`, the completed turn contained no disallowed
  item type, and two fresh App Server processes read/resumed the same identity
  with exactly one turn.
- A second complete live run passed in 0.931 seconds. It used the committed
  receipt, submitted no new task or turn, and again observed exactly one stored
  turn after restart.
- A redacted journal query returned one ready binding, one committed turn
  receipt, zero prepared turn receipts, and zero prepared binding receipts.
- Public validation results contain no provider thread or turn reference,
  workspace path, prompt text, account data, or raw App Server output.

### Audit and next step

- The AI-code audit made the fake provider enforce the exact prompt and policy,
  added persisted request/response fingerprint checks on retry, and rejected a
  changed response during idempotent turn commit.
- Two earlier zero-turn experiments were retained in recoverable local archive
  directories. Scoped reconciliation found no persistent provider task from
  either attempt; they are not completion evidence.
- M1-05 is next: integrate these durable Gateway capabilities into the native
  Mac command center so named Products, Projects, and Tasks can create or resume
  Codex work without entering a path or provider identifier.
- Hosted GitHub CI remains the pre-merge, external-contribution, and release
  gate recorded under F03.

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

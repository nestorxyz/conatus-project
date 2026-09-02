# Sequential Implementation Backlog

## Current Mac V1 sequence

ADR 0009 supersedes the mobile/Linux execution order below while preserving its
completed evidence. Work one ticket at a time:

```text
F01 Mac/Core/contracts foundation
  -> F02 durable domain kernel and failure tests
  -> F03 CI and local supervision boundary
  -> M1 named portfolio and Conatus-owned Codex tasks
  -> M2 account-managed natural voice on Mac
  -> M3 trusted Mac approvals and recovery
  -> M4 executive delegation and verified outcomes
  -> M5 signed launch-ready Mac V1
```

F01 must contain no live provider command, account creation, deployment, or
production credential. Android-specific tickets below are deferred, not passed.

**Status:** Initial execution plan

**Rule:** A ticket starts only when its dependencies and acceptance evidence are complete

### F01 Mac/Core/contracts foundation

**Status:** Complete on 2026-09-01. See `RESULT.md` and ADR 0009.

### F02 Durable domain kernel and failure tests

**Depends on:** F01

**Status:** Complete on 2026-09-01. See `RESULT.md` and ADR 0010.

**Outcome:** Implement the account-scoped PostgreSQL kernel defined by ADR 0010,
including the minimum identity, portfolio, orchestration, execution, event,
idempotency, and outbox records needed by M1. No public product endpoint, live
Codex command, provider account, deployment, or production data is included.

**Acceptance:** A disposable real-PostgreSQL check proves atomic aggregate/event/
outbox writes, cross-account negative reads and mutations, matching and
conflicting idempotent retries, exactly one optimistic-version winner, rollback
without fragments, and restart recovery through a fresh database connection.

### F03 CI and local supervision boundary

**Depends on:** F02

**Status:** Complete on 2026-09-01 through reproducible local Node 24, macOS
Swift, and disposable PostgreSQL verification; hosted CI is a pre-merge,
external-contribution, and release gate

**Outcome:** Run the Mac, Core, database migrations, and local Gateway boundary
through reproducible development supervision and CI without adding production
credentials or a public service binding.

**Acceptance:** The locked F03 gate runs Node 24 quality and disposable
PostgreSQL checks plus macOS Swift/TypeScript contracts and a bounded
fake-provider helper lifecycle. One helper restart is visible, a silent helper
times out, restart exhaustion stops, production mode rejects development auth,
and diagnostics expose no credential, transcript, workspace path, raw output,
or private provider reference. Hosted CI must pass before merge, external
contribution acceptance, or release. Signing and actual Codex execution remain
blocked.

### M1 Owned portfolio and task execution

**Depends on:** F03

**Status:** Complete on 2026-09-02. See `RESULT.md` and ADRs 0012 through 0016.

**User-visible outcome:** The Mac command center shows named projects, tasks,
blockers, and results. A user can create or resume a Conatus-owned Codex task
without remembering a repository path or provider task identifier.

M1 is delivered through the following dependency-ordered slices:

1. **M1-01 Codex compatibility pin:** exact non-experimental App Server schema
   digest, stable method allowlist, and Swift read-only request vectors.
2. **M1-02 Registered workspace and portfolio projection:** account-scoped
   workspace handles, names and aliases, deterministic ambiguity behavior, and
   a Core projection for Products, Projects, Tasks, blockers, and results.
3. **M1-03 Durable Codex binding and writer lease:** Conatus-owned opaque
   binding IDs, provider references behind the Gateway, local receipts, fencing,
   idempotent create/resume, and restart reconciliation.
4. **M1-04 Bounded real read-only lifecycle:** one approved account-backed
   create/resume fixture survives Gateway restart with exact identity and no
   duplicate turn.
5. **M1-05 Mac command center integration:** native portfolio/task UI routes by
   names and stable IDs, displays honest lifecycle/error state, and demonstrates
   the complete create/resume journey without path entry.

**Milestone acceptance:** An authenticated local development identity sees a
persistent named portfolio and registered workspace handles. The Gateway uses a
reviewed Codex schema pin and local receipts. A bounded read-only Conatus-owned
task survives restart with the same binding and provider identity, and a retry
does not create a duplicate turn. Provider references and absolute paths never
enter Core or client payloads. Effectful work remains blocked until trusted
approvals exist.

#### M1-01 Codex compatibility pin

**Depends on:** F03

**Status:** Complete on 2026-09-01. See `RESULT.md` and ADR 0012.

**Acceptance:** The exact Codex CLI version and generated non-experimental
schema digest are checked reproducibly; every allowlisted request/notification
is present; Swift emits stable initialize and task-lifecycle requests; thread
creation is structurally limited to read-only sandbox and approval policy
`never`; no provider process, account usage, or persistent Codex task is used.

#### M1-02 Registered workspace and portfolio projection

**Depends on:** M1-01

**Status:** Complete on 2026-09-01. See `RESULT.md` and ADR 0013.

**Acceptance:** Account-scoped Workspace handles and aliases resolve primary
names and spoken aliases without storing a path; ambiguous names return a
deterministic candidate set instead of selecting a target; a persistent Core
projection returns Products, Projects, Tasks, active blockers, and recent
results; a fresh connection observes the same state; cross-account reads and
mutations reveal nothing; projection payloads contain no absolute path or
provider reference.

#### M1-03 Durable Codex binding and writer lease

**Depends on:** M1-02

**Status:** Complete on 2026-09-01

**Outcome:** Added a Gateway-owned SQLite journal with canonical private
workspace registration, Conatus-owned opaque Task bindings, local-only provider
references, immutable create/resume receipts, immediate-transaction writer
leases, durable fence tokens, and redacted restart reconciliation. The journal
refuses newer schema versions and revalidates registered directories before
local use.

**Acceptance:** A Gateway-owned SQLite journal binds one Conatus Workspace to a
canonical local directory and one Task to an opaque binding; provider references
remain local and absent from redacted reconciliation; create/resume preparation
is idempotent; conflicting fingerprints fail; two journal connections prove one
live writer, expiry takeover with a higher fence, and stale-writer rejection; a
fresh connection recovers pending-create and resume-ready state without starting
Codex or using a provider account.

#### M1-04 Bounded real read-only lifecycle

**Depends on:** M1-03

**Status:** Complete on 2026-09-02

**Acceptance:** One explicitly approved account-backed provider thread is
created and receives exactly one fixed read-only, no-network, no-tools turn; its
final reply is exactly `CONATUS_M1_04_READY`; a fresh Gateway journal connection
and App Server process read and resume the same provider identity with one turn;
a complete retry issues neither another `thread/start` nor another `turn/start`;
public results expose no provider reference, path, prompt, account data, or raw
App Server output. Prepared-but-uncommitted create or turn dispatches fail
closed for manual reconciliation.

#### M1-05 Mac command center integration

**Depends on:** M1-04

**Status:** Complete on 2026-09-02. See `RESULT.md` and ADR 0016.

**Acceptance:** An authenticated loopback request derives its account entirely
from server-side identity and returns the persistent named portfolio without an
account ID, path, provider reference, credential, transcript, or raw output. The
native Mac UI navigates Products, Projects, and Tasks by stable Conatus IDs and
shows loading, fresh, empty, stale, unauthorized, unavailable, and malformed
states honestly. A Task activation crosses a narrow Gateway boundary containing
only Conatus Workspace and Task IDs. Disposable PostgreSQL and fake App Server
tests prove the read/create/restart/resume/retry journey without production
state or another account-backed Codex task.

### M2 Account-managed natural voice on Mac

**Depends on:** M1

**Status:** In progress; M2-01 is complete and M2-02 is next

**User-visible outcome:** A user says `Hey Conatus` and continues the command in
the same sentence. Conatus acknowledges immediately, transcribes post-wake audio
through the user's Conatus account, routes one committed turn to the named Task,
speaks useful status, accepts bounded follow-ups without another wake phrase,
and supports barge-in. No keyboard shortcut, Apple Speech transcription, or
user-supplied provider key is part of the launch path.

M2 is delivered through the following dependency-ordered slices:

1. **M2-01 Managed voice lifecycle contract:** provider-neutral lifecycle,
   transcript-free public status, same-utterance activation, exactly-once turn
   routing, follow-up, barge-in, cancellation, and recoverable failure behavior.
2. **M2-02 Local wake, capture, and feedback:** replaceable commercially
   distributable wake detection, pre-roll, local turn capture, microphone/audio
   route handling, and immediate audible/visible feedback. No local semantic
   transcription.
3. **M2-03 Account voice grants and quota:** authenticated short-lived voice
   admission, least-authority grants, per-account limits, revocation, abandoned
   session cleanup, and no provider credential on the Mac.
4. **M2-04 Realtime transcription adapter:** pinned provider contract, ordered
   partial/final reconciliation, deterministic fake transport, and one separately
   approved bounded live transcription validation.
5. **M2-05 Native conversation integration:** task routing, partial transcript
   presentation, committed command state, spoken status, follow-up, barge-in,
   cancellation, sleep/wake, network-loss, and audio-route recovery.

**Milestone acceptance:** Five same-sentence commands and two follow-ups route
exactly once; acknowledgement begins before cloud processing; no pre-wake audio
is uploaded and raw audio is not retained by default. Microphone denial, false
wake, provider outage, quota denial, network loss, sleep/wake, headset changes,
and barge-in are recoverable and visible. Cross-account voice grants fail, the
Mac contains no provider credential, and production command transcription does
not invoke Apple Speech.

#### M2-01 Managed voice lifecycle contract

**Depends on:** M1-05

**Status:** Complete on 2026-09-02. See `RESULT.md` and ADR 0017.

**Acceptance:** ADR 0017 and shared Swift/TypeScript vectors define the exact
transcript-free public voice states. A deterministic native state machine proves
same-utterance acknowledgement and capture, partial/final separation, one route
per provider-neutral Voice Turn ID, continuous follow-up, barge-in,
cancellation, and network recovery. Public status contains no audio, transcript,
provider identifier, credential, path, raw output, or Codex reference. This
ticket requests no microphone permission and makes no provider call.

## How to use this backlog

- One ticket should produce one reviewable change or a deliberately small series of linked changes.
- Every ticket includes automated tests unless it is explicitly a research, design, or operational exercise.
- Security, protocol, and persistence behavior must be tested at the layer where it is enforced.
- A ticket cannot weaken an invariant to make a demo pass.
- New discoveries update the relevant specification or ADR before implementation diverges.
- `P-*`, `S-*`, and `A-*` refer to the product, security, and alpha acceptance invariants.

## Phase 0: Decisions and repository foundation

### C-001 Confirm licensing and contribution model

**Depends on:** none  
**Status:** Complete on 2026-08-09 by founder risk acceptance; no qualified legal review was performed  
**Outcome:** The founder adopted AGPL-3.0-or-later, the dependency policy, DCO contributor terms, and the documented iOS distribution constraints. The founder explicitly waived legal review as a repository-foundation gate; narrower legal gates remain before external contributions, distributed iOS builds, or relicensing. Added `LICENSE`, SPDX policy, contribution guide, code of conduct, security disclosure instructions, and a licensing validation script.  
**Acceptance:** License scanner recognizes the project; prohibited or incompatible dependency classes are documented; no claim that AGPL alone prevents all private use.

### C-002 Create monorepo skeleton and ownership boundaries

**Depends on:** C-001  
**Status:** Complete on 2026-08-09
**Outcome:** Create `apps/mobile`, `agents/machine`, `services/control-plane`, `packages/protocol`, and `packages/test-vectors`, each with an owner, README, build entry point, and dependency boundary.  
**Acceptance:** Clean checkout runs a single documented bootstrap and verifies every empty component without global machine mutation.

### C-003 Establish CI quality and supply-chain baseline

**Depends on:** C-002  
**Status:** Complete on 2026-08-09

**Outcome:** Added local and GitHub CI gates for bootstrap, formatting, shell lint and tests, dependency locks, secret patterns, licensing, dependency-license inventory, and CycloneDX SBOM generation. GitHub Actions are commit-pinned, and signed-tag release validation is gated by the protected `release` environment. Negative fixtures record all four required failure modes.
**Acceptance:** A deliberately malformed format, test failure, fake secret, and prohibited license each fail CI in a fixture or recorded validation.

### C-004 Select Rust web stack through a spike

**Depends on:** C-002  
**Status:** Complete on 2026-08-09
**Outcome:** Compared Axum and Actix Web and selected Axum in ADR 0002. A locked,
disposable loopback harness verifies authenticated WebSockets, bounded-queue
backpressure, trace instrumentation, graceful shutdown, and 96 reconnect cycles.
**Acceptance:** The selected stack passes a small load/reconnect harness and the rejected option is explained without building production services.

### C-005 Select iOS terminal rendering approach

**Depends on:** C-001, C-002  
**Status:** Deferred on 2026-08-09 by ADR 0004 until physical iPhone hardware is available
**Outcome:** Evaluate candidate terminal parser/renderers for license, UTF-8, ANSI/OSC safety, accessibility, performance, selection, and native Swift integration; record ADR.
**Acceptance:** Prototype renders the malicious-terminal corpus and a long scrollback trace on a physical iPhone without unsafe side effects.

### C-006 Select identity provider

**Depends on:** C-001  
**Status:** Complete on 2026-08-11
**Outcome:** Evaluated WorkOS AuthKit, Clerk, Auth0, and self-hosted Keycloak and
selected WorkOS AuthKit in ADR 0007. Conatus retains authoritative
organization authorization, device and machine trust, and durable security
audit records. Native clients use a public-client system-browser authorization
code flow with PKCE, subject to the C-050 conformance proof.
**Acceptance:** Document login, refresh, logout, lost-device, provider outage, and migration behavior.

### C-007 Complete cryptographic design review

**Depends on:** C-001  
**Status:** In progress; ADR 0008 and the independent-review packet were
prepared on 2026-08-11. No independent reviewer is assigned, so the acceptance
gate remains open and production cryptography remains blocked. An AI-assisted
pre-review identified one Critical and six High composition findings and
produced an ordered remediation plan; it is advisory work and does not satisfy
the independent-review gate.

**Outcome:** Specify device/machine identity, pairing transcript, per-session keys, key wrapping, rotation, recovery, revocation generation, algorithms, libraries, and metadata authentication.  
**Acceptance:** Independent expert review closes all critical/high findings before production cryptography is implemented.

**Remediation progress:** C-007-R1 design is complete on 2026-08-12. The
[authority state model](protocol/cryptographic-authority-state.md) defines
paired endpoint trust, a single mobile content authority, target-machine linear
commits, signer predicates, forks, partitions, revocation, and a semantic
adversarial case matrix. This is remediation evidence, not independent closure.
C-007-R2 was the next dependency-unblocked design work package.

**C-007-R2 update:** Pairing and recovery ceremony design is complete on
2026-08-12. The fixed `Noise_XXpsk3_25519_ChaChaPoly_SHA256` construction,
one-attempt secret lifecycle, comparison and confirmation exchange,
trusted-device recovery, local-machine recovery, and 24 semantic adversarial
cases are documented. This is remediation evidence, not independent closure.
C-007-R3 was the next dependency-unblocked work package.

**C-007-R3 update:** Sender-authentication design is complete on 2026-08-12.
Eligible endpoint signatures are verified before durable decryption or action,
artifacts remain quarantined until sender-signed finalization, and every PTY
lease/reconnect uses a fresh pairwise `Noise_KK_25519_ChaChaPoly_SHA256`
channel with pre-execution frame checks. Thirty semantic adversarial cases are
documented. This is remediation evidence, not independent closure. C-007-R4 is
the next dependency-unblocked work package.

**C-007-R4 update:** Nonce/crash semantic design is complete on 2026-08-12.
Signed sender-incarnation grants, transactional counter allocation, immutable
persist-before-send replay, artifact abandonment/restart, fresh PTY handshakes,
typed uncertainty failures, supported restore boundaries, and 30 semantic fault
cases are documented. Exact live-memory clones without trusted fresh entropy
are explicitly unsupported and quarantined. This is remediation evidence, not
executable validation or independent closure. C-007-R5 is the next
dependency-unblocked work package.

**C-007-R5 update:** The normative version-1 byte design is complete on
2026-08-12. Closed CDDL maps, strict deterministic CBOR, detached COSE_Sign1,
raw low-S ES256, purpose-bound key IDs, labeled hashes and HKDF, canonical HPKE
pre-manifest/recipient inputs, AEAD projections, Noise contexts, an exact
positive primitive fixture, and 45 negative confusion cases are documented.
The fixture also covers all 32 version-1 body/projection branches; its ES256
signature and HPKE open were independently reproduced in the workspace. This
includes the RFC 9180 Appendix A.2.1 base-mode vector. This is design and
language-neutral vector evidence, not
cross-language implementation evidence or independent closure. C-007-R6 is the
next dependency-unblocked work package.

**C-007-R6 update:** The disposable platform-boundary prototype is partially
complete on 2026-08-13. A 133-package checksum-locked Rust graph compiles for
Linux and Android arm64; the direct dependency/license inventory and a current
RustSec scan are recorded. Host tests cover the R5 ES256/JCA boundary, strict
DER and low-S handling, COSE output, malformed inputs, Linux single-writer
locking, atomic immutable publication, injected crashes, ownership, modes,
restore, and idempotent unlink on ext4. AddressSanitizer coverage-guided fuzzing
also passes for strict DER parsing and the platform-neutral owned JNI/COSE
buffer boundary, including observable input clearing on every return path. The
Android APK compiles with separate Keystore identity/approval keys, per-use
biometric approval, per-private-key AES-GCM wrapping keys, bounded
panic-contained JNI, security-posture reporting, and backup/D2D exclusions.
A non-destructive wrapped-fixture/JNI reload process-death probe also passes on
the API-28 Moto G6 Plus after an operator force-stop and relaunch. Newer-device,
credential-fallback, remaining lifecycle, and backup evidence remains open.
Non-ext4 durable-security-state filesystems are outside the now-explicit
ext4-only alpha scope and fail closed pending separate evidence. The actual
Java/JNI negative and concurrency harness
passes 92 rejection cases, 256 synchronized calls, and valid recovery on the
same API-28 device; sudden-death-during-JNI remains open. C-007-R6 is not closed
and C-007-R7 is still blocked. Local key-first cryptographic-deletion tests pass
three injected failure stages and idempotent retry. A private same-UID Android
subprocess reached native abort without returning on its first device run, but
the volatile observer left UI survival inconclusive. A corrected parent-PID and
polling build then passed on API 28: the original main process displayed PASS
and remained alive after Android removed the visible task, while the probe
process was absent. Remaining device-matrix coverage is still open. This is
fault evidence only, not a production isolation architecture. The dependency and
platform assumption audit is recorded with the remaining production-selection
gaps. The final current-state R6 gap report, pinned to implementation commit
`1e4ab9c9004a59e0ea4517ba1d477a6fb2762fe4`, assigns the remaining findings,
validation evidence, owners, and gate dates. It explicitly withholds R6 closure
and production-implementation authorization.

### C-008 Select Android terminal rendering approach

**Depends on:** C-001, C-002
**Status:** Complete 2026-08-23. ADR 0005 accepts the Conatus-owned Kotlin view
backed by `alacritty_terminal` 0.26.0. The final API-28 physical-device release
run completed all 21 cases in 505 ms without a sensitive permission prompt or
observed external side effect. Peak PSS was conservatively recorded as 113.1
MiB and the post-destroy delta as 9.7 MiB. Scrollback, exact-line selection,
lifecycle recreation, rotation, largest-font-scale usability, and per-line
TalkBack traversal passed. The tracked sanitized report records the toolchain,
revision, checksum, and aggregate evidence; the device handoff retains the
failed precursor runs and their remediations.
**Outcome:** Evaluate established permissively licensed Android terminal parser/renderers and a native Kotlin renderer backed by a Rust parser for UTF-8, ANSI/OSC safety, TalkBack, performance, selection, Compose/View hosting, and JNI integration; record ADR.
**Acceptance:** Prototype renders the malicious-terminal corpus and a 10,000-line scrollback trace on a physical Android phone without unsafe side effects. Record device, Android/Gradle/JDK versions, duration, peak memory, lifecycle, selection, largest-font-scale, and TalkBack evidence.

## Phase 1: Protocol and deterministic core

### C-010 Define protocol schemas and error taxonomy

**Depends on:** C-004, C-007  
**Outcome:** Add versioned Protobuf handshake, envelope, session, run, approval, PTY, artifact, and error schemas.  
**Acceptance:** Rust and Kotlin generation succeeds; schema lint and compatibility rules run in CI. Add Swift generation before resumed iOS implementation.

### C-011 Add protocol golden vectors

**Depends on:** C-010  
**Outcome:** Canonical binary/JSON diagnostic vectors cover known, unknown, malformed, oversized, and previous-version messages.  
**Acceptance:** Rust and Kotlin independently parse and re-emit every preservation vector identically where required; future Swift bindings must pass the same vectors.

### C-012 Implement canonical operation model

**Depends on:** C-010  
**Outcome:** Rust types and canonical encoding cover executable, arguments, directory, environment hashes, resources, actor, machine, policy, nonce, and expiration.  
**Acceptance:** Golden vectors cover Unicode, ordering, symlinks, environment changes, and ambiguous shell operations.

### C-013 Implement policy engine

**Depends on:** C-012  
**Outcome:** Deterministic `allow`, `prompt`, or `deny` evaluation implements [approval-policy.md](approval-policy.md).  
**Acceptance:** Table-driven tests cover every policy row; unknown operations and versions fail closed (`S-002`, `S-004`, `S-008`).

### C-014 Implement run state reducer

**Depends on:** C-010  
**Outcome:** Pure reducer derives run state from events and rejects invalid terminal-state transitions.  
**Acceptance:** Property tests cover ordering, duplicates, cancellation, approval, disconnect, and unknown outcome (`P-013`–`P-016`).

### C-015 Implement block projection core

**Depends on:** C-014  
**Outcome:** A deterministic projection core consumable from Kotlin creates fallback, user, command, approval, agent, error, Git, and test blocks from events; choose pure Kotlin or a bounded shared Rust core before implementation.
**Acceptance:** Rebuilding from the same event stream is deterministic; unknown events survive and render safely (`P-031`–`P-034`).

## Phase 2: Control-plane durable kernel

### C-020 Model organizations and memberships

**Depends on:** C-006, C-010  
**Outcome:** PostgreSQL schema and authorization service support personal/company organizations and multiple memberships.  
**Acceptance:** Cross-tenant negative tests cover every query and mutation (`P-001`, `S-006`).

### C-021 Model devices, machines, workspaces, and revocation

**Depends on:** C-020, C-007  
**Outcome:** Durable identities, public keys, statuses, organization ownership, workspace grants, and revocation generations.  
**Acceptance:** Departure and revocation transaction tests match ADR 0001 and `A-015`.

### C-022 Implement sessions, runs, and transactional event append

**Depends on:** C-020, C-010, C-014  
**Outcome:** Session stream allocates sequence numbers and appends encrypted envelopes transactionally.  
**Acceptance:** Concurrent writers produce gap-explained monotonic order; duplicate event IDs do not duplicate effects (`P-010`–`P-012`).

### C-023 Implement idempotent run submission

**Depends on:** C-022  
**Outcome:** HTTP submission creates one run per scoped idempotency key and reports accepted versus unknown outcome.  
**Acceptance:** Timeout/retry and concurrent duplicate tests produce one run (`A-003`, `P-055`).

### C-024 Implement replay, cursor, and snapshot API

**Depends on:** C-022  
**Outcome:** Clients fetch ordered events after a cursor and recover from a compacted cursor through a snapshot.  
**Acceptance:** Random disconnect property test reconstructs the same projection without duplication (`A-005`).

### C-025 Implement connection router

**Depends on:** C-004, C-021, C-024  
**Outcome:** Authenticated mobile and machine WebSockets route opaque envelopes with bounded queues, leases, acknowledgement, and graceful drain.  
**Acceptance:** Router restart, slow consumer, duplicate frame, and reconnect-storm tests pass; no authoritative run state exists only in memory.

### C-026 Implement durable approvals

**Depends on:** C-012, C-022  
**Outcome:** Approval challenges, signed decisions, expiry, conflict resolution, revocation check, and atomic consumption.  
**Acceptance:** Mutation, replay, simultaneous decision, expiry, and operation-change tests pass (`P-040`–`P-046`).

### C-027 Add content-safe observability

**Depends on:** C-022, C-025  
**Outcome:** Metrics, traces, structured logs, security audit stream, and automated content leakage tests.  
**Acceptance:** Synthetic secrets, commands, paths, prompts, and diffs do not appear in ordinary telemetry (`P-050`, `S-009`).

## Phase 3: Linux machine agent

### C-030 Create Linux service lifecycle

**Depends on:** C-002, C-010  
**Outcome:** Unprivileged Linux daemon installs as a user service, loads external configuration, reports health/version, and shuts down cleanly.  
**Acceptance:** Install, upgrade, restart, crash, and uninstall tests preserve user files and require no root for normal operation.

### C-031 Implement pairing and protected key storage

**Depends on:** C-007, C-021, C-030  
**Outcome:** Linux agent creates keys, conducts short-lived mutual pairing, and stores credentials with least privilege.  
**Acceptance:** Replay, expired challenge, substituted key, wrong organization, and permission tests pass (`A-001`).

### C-032 Implement machine connection and resend buffer

**Depends on:** C-025, C-031  
**Outcome:** Agent maintains outbound connection, verifies negotiation/revocation, and resends unacknowledged bounded frames.  
**Acceptance:** Network, router, and agent restarts reconcile without invented completion (`A-011`).

### C-033 Implement workspace grants and canonical paths

**Depends on:** C-013, C-031  
**Outcome:** User explicitly grants regular Linux directories; path handling resists traversal and symlink escape.  
**Acceptance:** Filesystem race and malicious path suite passes; secret paths remain denied.

### C-034 Implement structured process executor

**Depends on:** C-032, C-033, C-013  
**Outcome:** Execute argument vectors with directory, environment, output, time, concurrency, process-tree cancellation, and backpressure controls.  
**Acceptance:** Stdout/stderr identity, exit, truncation, cancellation, output flood, and idempotent admission tests pass (`A-002`, `A-003`).

### C-035 Connect policy and approval consumption

**Depends on:** C-026, C-034  
**Outcome:** Linux agent canonicalizes, classifies, prompts, verifies signed decision, re-resolves, and atomically admits work.  
**Acceptance:** Full approval adversarial suite passes on the machine (`A-004`, `A-010`).

### C-036 Add Git observation adapter

**Depends on:** C-033, C-034  
**Outcome:** Bounded, read-only status and diff observations with stale-state metadata and raw evidence artifact.  
**Acceptance:** Large, binary, renamed, untracked, malicious filename, and non-repository cases pass.

## Phase 4: Essential PTY

### C-040 Implement Linux PTY manager

**Depends on:** C-032, C-033  
**Outcome:** Create, resize, input, output, signal, terminate, checkpoint, and reap PTYs under an exclusive input lease.  
**Acceptance:** Real Bash plus UTF-8, resize, alternate screen, signals, child exit, and output flood tests pass.

### C-041 Implement PTY protocol and reconnect

**Depends on:** C-040, C-025  
**Outcome:** Ordered bounded frames, acknowledgement, checkpoint, lease transfer, and unavailable-history signaling.  
**Acceptance:** Random disconnect test restores a coherent screen and labels missing history (`P-023`).

### C-042 Integrate Android terminal core

**Depends on:** C-008, C-041
**Outcome:** The native Kotlin app integrates the selected Rust terminal core, custom Android terminal view, and binary PTY frames through the bounded JNI API.
**Acceptance:** Physical-device performance, background/foreground, memory pressure, rotation, and parser-security tests pass.

### C-043 Implement mobile terminal controls

**Depends on:** C-042  
**Outcome:** Esc, Tab, Ctrl, arrows, selection, copy, paste preview, lease state, reconnect, and exit UI.  
**Acceptance:** `A-009`, VoiceOver navigation, dynamic type, and multiline/control-bearing paste tests pass.

### C-044 Validate generic CLI agents in PTY

**Depends on:** C-043  
**Outcome:** Test installed stable Codex, Claude Code, and Gemini CLI interactively without special parsing.  
**Acceptance:** Start, authenticate through provider-supported local flow, operate, interrupt, resize, disconnect, and resume terminal observation (`A-008`).

## Phase 5: Android product shell

### C-050 Implement authentication and secure local session

**Depends on:** C-006, C-020  
**Outcome:** OIDC/PKCE sign-in, protected device key, token rotation, logout wipe, and reauthentication.  
**Acceptance:** Token theft, logout, refresh race, offline, and lost-device scenarios pass.

### C-051 Implement organization and machine home

**Depends on:** C-050, C-021, C-025  
**Outcome:** Separate personal/company contexts, machine reachability, active runs, pending approvals, completions, and stale-state UI.  
**Acceptance:** No recents or cached content leak across organization switching (`P-004`, `P-005`).

### C-052 Implement Android pairing flow

**Depends on:** C-031, C-050  
**Outcome:** Scan/enter challenge, compare identity, confirm, expire, recover, and revoke.  
**Acceptance:** UX and security pairing scenarios pass on physical Android devices (`A-001`).

### C-053 Implement session timeline and local projections

**Depends on:** C-015, C-024, C-050  
**Outcome:** Encrypted cache, pagination, virtualization, replay, live merge, stale markers, and raw evidence navigation.  
**Acceptance:** Ten thousand lightweight events scroll within budget; random reconnect yields identical projection.

### C-054 Implement composer and context selection

**Depends on:** C-051, C-053, C-033  
**Outcome:** Machine/workspace context, `$` shell, `/` internal command, and natural-language routing with visible execution mode.  
**Acceptance:** Submission is impossible under stale, offline, unauthorized, or ambiguous context.

### C-055 Implement approval UI

**Depends on:** C-026, C-035, C-053  
**Outcome:** Exact canonical operation, risk, resources, actor, expiry, approve/reject, conflict, and changed-operation UI.  
**Acceptance:** Interactive prototype usability threshold is met; destructive approval requires in-app final gesture.

### C-056 Implement command, Git, error, and recovery blocks

**Depends on:** C-034, C-036, C-053  
**Outcome:** Mobile structured renderers with raw evidence, truncation, stale observation, cancellation, and retry-as-new-run.  
**Acceptance:** `P-020`–`P-025`, `P-032`–`P-034`, and Git edge cases pass.

## Phase 6: Codex structured adapter

### C-060 Build provider contract harness

**Depends on:** C-003, C-034  
**Outcome:** Disposable Linux test repository captures sanitized golden provider streams for the cases in [agent-adapter-evaluation.md](agent-adapter-evaluation.md).  
**Acceptance:** Exact tested Codex version and expected JSONL contracts are recorded; secrets are absent.

### C-061 Implement generic adapter supervisor

**Depends on:** C-060, C-034  
**Outcome:** Version discovery, process lifecycle, incremental bounded JSONL parser, raw event preservation, cancellation, and provider error taxonomy.  
**Acceptance:** Malformed, oversized, unknown, interrupted, incompatible, and authentication-error fixtures pass.

### C-062 Implement Codex normalization

**Depends on:** C-061  
**Outcome:** Map thread, turn, item, message, command, file change, tool, usage, error, and completion events without losing provider identity.  
**Acceptance:** Golden streams create expected Conatus events and fallback blocks (`A-006`).

### C-063 Implement Codex resume

**Depends on:** C-062  
**Outcome:** Persist provider session ID and resume only that explicit ID with a follow-up prompt.  
**Acceptance:** Correct, missing, expired, incompatible-version, and wrong-workspace cases pass (`A-007`).

### C-064 Integrate Conatus approval posture

**Depends on:** C-035, C-062  
**Outcome:** Launch Codex with supported non-bypass sandbox/approval configuration and normalize operations into Conatus policy where supported.  
**Acceptance:** No dangerous bypass flag exists in production paths; provider approval cannot weaken Conatus policy.

### C-065 Implement agent blocks and monitoring

**Depends on:** C-053, C-062, C-063  
**Outcome:** Start and monitor Codex from home/session, render structured progress, resume, cancel, inspect raw evidence, and fall back to PTY for unsupported versions.  
**Acceptance:** Monitoring and starting work are equally reachable; all provider states survive app disconnect.

## Phase 7: Railway internal alpha

### C-070 Define Railway infrastructure as code

**Depends on:** C-004, C-022, C-025, C-027  
**Outcome:** Separate environments, persistent services, private networking, PostgreSQL, health checks, secrets, limits, and deploy configuration. Serverless sleep is disabled for routers.  
**Acceptance:** A clean Railway environment deploys from documented configuration without manual secret disclosure.

### C-071 Implement database backup and restore exercise

**Depends on:** C-070  
**Outcome:** Automated backup policy and isolated restore runbook.  
**Acceptance:** `A-014` passes with measured recovery point/time and verified encrypted artifact references.

### C-072 Run Railway connection acceptance suite

**Depends on:** C-070, C-032, C-053  
**Outcome:** Measure connection lifetime, deployment drain, router crash, replica change, and reconnect wave on the chosen plan/region.  
**Acceptance:** `A-012` passes; observed constraints are recorded and protocol timeouts updated through ADR if needed.

### C-073 Create signed internal release pipeline

**Depends on:** C-003, C-030, C-050, C-070  
**Outcome:** Signed Linux agent and Android internal builds, provenance, SBOM, staged environment promotion, and rollback.
**Acceptance:** Tampered artifact is rejected; previous version can be restored without schema loss.

### C-074 Conduct alpha security review

**Depends on:** C-055, C-064, C-072, C-073  
**Outcome:** Threat-model verification, parser fuzz results, isolation test, mobile review, Linux-agent review, and remediation.  
**Acceptance:** No open critical/high finding; all accepted residual risks have owner and review date.

### C-075 Dogfood and alpha exit report

**Depends on:** C-044, C-056, C-065, C-071, C-074  
**Outcome:** Two-week internal dogfood with reliability, reconnect, approval clarity, terminal usage, privacy, and retention metrics.  
**Acceptance:** Every `A-*` scenario has linked evidence; alpha exit criteria are met or explicitly rejected with a follow-up ticket.

## Post-alpha candidate order

1. Claude Code structured adapter
2. Organization invitations and roles
3. Push notifications without sensitive previews
4. Gemini CLI structured adapter
5. Signed automatic Linux-agent updates
6. Team audit export and policy management
7. Resume iOS renderer and product work
8. App Store release preparation
9. Billing and plan enforcement

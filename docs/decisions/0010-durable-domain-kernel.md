# ADR 0010: Account-scoped durable domain kernel

**Status:** Accepted
**Date:** 2026-09-01
**Depends on:** ADR 0009

## Context

The Mac-first product needs durable identity, portfolio, command, delivery, and
execution records before it can safely create or resume Codex-owned tasks. An
in-memory queue or unscoped object lookup would make restart recovery,
idempotency, and account isolation unprovable.

F02 establishes the minimum persistence contract without adding authentication,
voice, live Codex execution, deployment, or production customer data.

## Decision

- PostgreSQL is the authoritative F02 store.
- `Account` is the isolation root. Every remotely stored child record carries
  `account_id`, and joins use composite account-scoped foreign keys.
- F02 persists the minimum boundaries for Account, Principal, Device, Machine,
  Workspace, Product, Project, Task, Command, Delivery, ExecutionAttempt,
  DomainEvent, IdempotencyRecord, and OutboxRecord.
- Application-generated IDs are UUIDv7 values. Names, paths, and provider IDs
  never define Conatus identity.
- Mutable aggregates use monotonically increasing optimistic versions. A stale
  expected version fails without mutating state.
- One transaction commits an accepted aggregate transition, its append-only
  DomainEvent, and its OutboxRecord. There is no state change without matching
  recovery evidence.
- Idempotency is scoped by account, actor, operation, and key. Replaying the same
  request fingerprint returns the existing result; reusing the key for a
  different fingerprint is a conflict.
- Command, Delivery, and ExecutionAttempt remain separate records. A duplicate
  command admission cannot silently create another execution attempt.
- Database access is exposed through account-scoped repository operations. Raw
  client-supplied account identifiers are not authorization; later HTTP work
  must obtain account scope from authenticated server context.

## F02 operations

F02 proves these narrow operations:

1. atomically create an Account and its single owner Principal;
2. atomically create a Workspace, Product, Project, and first Task;
3. read and rename a Task only inside the supplied account scope;
4. reject stale Task versions;
5. admit one semantic Command per scoped idempotency key and fingerprint;
6. create one Delivery and one ExecutionAttempt for that Command;
7. recover accepted state, events, and pending outbox work after reconnecting a
   new repository instance to the database.

These are kernel proofs, not public product APIs.

## Consequences

- F02 requires a real disposable PostgreSQL integration check. Unit-only mocks
  cannot satisfy its transaction or isolation evidence.
- F02 stores no absolute workspace path, transcript, provider credential,
  provider conversation reference, source code, or command output.
- Authentication, policy evaluation, leases/fencing, approvals, verification,
  projections, retention automation, and provider adapters remain later
  tickets. Their schema may extend this kernel without weakening its isolation
  and transaction invariants.
- PostgreSQL provisioning and production migrations remain unapproved; the F02
  database is disposable local test infrastructure only.

## Verification

- Cross-account reads and mutations return no record and change no state.
- Conflicting idempotency fingerprints are rejected.
- Concurrent or repeated stale versions permit exactly one accepted transition.
- Injected failure before commit leaves no aggregate, event, or outbox fragment.
- Every accepted transition has one matching event and outbox record.
- A new database connection observes the same durable state and pending outbox.

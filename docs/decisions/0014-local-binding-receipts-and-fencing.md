# ADR 0014: Local workspace bindings, receipts, and fencing

**Status:** Accepted for M1
**Date:** 2026-09-01
**Depends on:** ADR 0010, ADR 0012, and ADR 0013

## Context

Core can now identify a Workspace and Task without a path, but Codex App Server
requires a local working directory and returns provider-owned thread IDs. Those
machine-private values must remain behind the Mac Gateway. A crash between
preparing and recording a create/resume operation must not create a second
Codex task, and two Gateway processes must not both believe they are the writer.

M1-03 establishes this local durability boundary without starting App Server,
using a provider account, or creating a real provider task.

## Decision

- Store local workspace paths, provider thread references, operation receipts,
  and writer leases in a Gateway-owned SQLite journal. Core and client payloads
  receive only Conatus-owned opaque binding IDs and redacted state.
- Register a Workspace against one canonical, existing local directory. Resolve
  symlinks before persistence. A different path cannot silently replace an
  existing registration.
- Bind one Conatus Task to one Workspace and one opaque local binding ID. A
  provider thread reference is nullable until a synthetic or real create result
  is committed.
- Fence writers by Conatus Task ID. Acquiring an absent or expired lease
  increments a durable integer token. Every preparation and commit verifies the
  current holder, token, resource, and expiry inside an immediate transaction.
- Treat operation receipts as immutable idempotency evidence. Reusing a key
  with the same fingerprint returns the original receipt; a different
  fingerprint is a conflict.
- Permit only two preparation kinds: create and resume. A Task with a pending
  create returns the existing pending receipt even if a caller invents a new
  key. A Task with a committed provider binding cannot prepare another create.
- A create commit records the provider thread reference locally. A resume
  commit records only that the prepared resume was accepted; it does not change
  provider identity.
- Reconciliation reports only unbound, create-pending, or resume-ready plus
  Conatus binding/receipt IDs. It never returns the workspace path or provider
  thread reference.
- SQLite uses foreign keys, WAL journaling, full synchronous durability, and a
  private local database file. The journal is not synced to Core or Git.

## Failure behavior

- Relative paths, missing directories, regular files, silent path replacement,
  empty identifiers, and empty provider references fail closed.
- An unexpired lease held by another writer returns a typed busy result.
- A stale holder or fence token cannot prepare or commit after lease takeover.
- A resume without a committed provider binding and a create against an already
  committed binding fail without changing journal state.
- An idempotency fingerprint conflict never returns the previous receipt.

## Consequences

- M1-04 can connect the reviewed App Server adapter to these preparation and
  commit boundaries without changing Core identity semantics.
- Provider references are recoverable on the Mac but intentionally absent from
  remote diagnostics and portfolio projections.
- Moving a repository requires an explicit future rebind ceremony; automatic
  path guessing is outside M1-03.
- Lease duration and renewal policy remain runtime concerns. M1-03 proves
  acquisition, expiry takeover, fencing, and release semantics.

## Verification

- Disposable local journals prove canonical directory registration and reject
  unsafe path inputs.
- Two journal connections prove one live writer, expiry takeover with a higher
  fence, and stale-writer rejection.
- Repeated create/resume preparation returns one receipt and one binding;
  changed fingerprints conflict.
- Fresh journal connections reconcile pending-create and committed-resume state
  without exposing a path or provider reference.
- No Codex process or provider account is used by the test suite.

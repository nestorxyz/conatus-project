# ADR 0013: Named portfolio projection and reference resolution

**Status:** Accepted for M1
**Date:** 2026-09-01
**Depends on:** ADR 0010 and ADR 0012

## Context

Conatus must let a user say or select a Product, Project, Workspace, or Task by
an understandable name without remembering a repository path or a Codex
provider identifier. Names and aliases are user-facing references, not durable
identity. The same phrase can legitimately identify more than one Task, so a
resolver that silently picks the first database row would route work
incorrectly.

M1-02 also needs one restart-safe command-center projection containing active
blockers and recent result summaries. It does not yet expose an HTTP API, bind a
local filesystem path, start Codex, or persist provider output.

## Decision

- Continue to use account-scoped UUIDv7 identifiers as authoritative identity.
- Treat a Workspace's account-unique slug as its public Conatus handle. Store
  additional Workspace, Product, Project, and Task aliases separately from the
  primary display name.
- Normalize lookup text with one application-owned function. Resolution checks
  stable Conatus ID, primary slug, and normalized aliases inside the authorized
  account scope.
- Allow an alias to identify multiple entities. Zero matches returns not found;
  one returns the exact entity; multiple return a typed ambiguity containing a
  deterministic, sorted list of safe Conatus candidates. The resolver never
  guesses.
- Permit an optional parent Conatus ID when resolving Projects or Tasks. This
  is the explicit disambiguation mechanism used after a user chooses context.
- Build the command-center read model from authoritative Workspace, Product,
  Project, Task, active-blocker, recent-result, and alias records under one
  repeatable-read snapshot.
- Keep active blocker summaries and at most five recent result summaries per
  Task in the first projection. They are product records, not raw Codex output.
- Every alias, blocker, and result mutation increments the owning aggregate
  version and atomically appends its DomainEvent and OutboxRecord.
- Store no absolute path, source code, transcript, provider thread/turn ID,
  credential, or raw command output in Core portfolio records or projection
  payloads.

## Failure behavior

- Empty or punctuation-only references fail before querying persistence.
- Cross-account reads and mutations behave as not found and reveal no candidate
  metadata.
- Ambiguity is a normal routing state, not a transient database error. Candidate
  ordering is stable by display name and Conatus ID.
- Projection reads fail as a unit rather than returning a mixture of database
  snapshots.

## Consequences

- A local workspace path mapping remains a Gateway-owned concern for M1-03.
- Future clients can render an ambiguity choice without learning a path or
  provider identifier.
- Aliases are intentionally non-unique across targets; callers must preserve
  the typed ambiguity path.
- Search ranking, semantic matching, fuzzy guessing, and model-selected routing
  remain outside M1-02.

## Verification

- Disposable PostgreSQL tests prove primary-name and alias resolution,
  deterministic ambiguity, explicit parent disambiguation, and account
  isolation.
- A fresh Core connection observes the same named projection, active blocker,
  recent result, and aliases.
- Projection serialization is checked for forbidden path and provider fields.
- Events and outbox records remain one-to-one after M1-02 mutations.

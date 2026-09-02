# ADR 0016: Authenticated loopback command-center boundary

**Status:** Accepted for M1
**Date:** 2026-09-02
**Depends on:** ADR 0013, ADR 0014, and ADR 0015

## Context

M1-05 connects the native Mac command center to the persistent named portfolio
without moving Core policy into Swift or exposing Gateway-private workspace
paths and Codex provider references. The UI must also distinguish Core
availability from task execution state instead of presenting optimistic status.

## Decision

- Core exposes `GET /v1/command-center` only to loopback callers. The route is
  unavailable unless an identity resolver and portfolio reader are explicitly
  installed at startup.
- Authentication resolves the account on the server. Account identifiers are
  forbidden in the request and omitted from the response; the client cannot
  select or override tenancy.
- The versioned response contains only Conatus-owned names, stable IDs, aliases,
  lifecycle summaries, active blockers, recent results, and an observation
  timestamp. It contains no filesystem path, provider reference, credential,
  prompt, transcript, or raw provider output.
- The Mac app uses a native, read-only HTTP client for this projection. It
  models loading, fresh, empty, stale, unauthorized, unavailable, and malformed
  response states explicitly.
- Task activation crosses a separate in-process Gateway protocol using only
  Conatus Workspace and Task IDs. The Gateway alone resolves a registered local
  path and provider binding. The UI receives a redacted binding state, never a
  Codex thread identifier.
- M1-05 validates create, restart, resume, and retry with the fake App Server and
  a disposable local PostgreSQL instance. It does not create another
  account-backed Codex task, deploy Core, or modify production data.

## Failure behavior

- Missing or invalid authentication returns a generic unauthorized response.
- A non-loopback caller receives a forbidden response before portfolio access.
- Database or contract failures return a generic unavailable response and do
  not serialize internal errors.
- A stale cached snapshot remains visibly stale; it is never relabeled fresh.
- Pending or uncertain Gateway receipts remain blocked for reconciliation and
  are never converted into a second create or turn request.

## Consequences

- The native UI can navigate Products, Projects, and Tasks without repository
  paths while Core remains the portfolio source of truth.
- The local HTTP surface is narrow and authenticated, but production identity
  verification and deployment remain separate future work.
- Provider lifecycle evidence can be merged into the selected Task locally
  without widening the Core or client contracts.

## Verification

- TypeScript and Swift accept the same valid command-center vector and reject a
  vector containing an account identifier and provider reference.
- Core route tests prove loopback and authentication enforcement, account
  derivation, response redaction, and generic failure behavior.
- A disposable PostgreSQL test serves a persistent named portfolio through the
  route and verifies the payload contains no forbidden private fields.
- Swift tests prove navigation selection and every honest loading/error state.
- The fake App Server lifecycle proves create/resume identity and retry behavior
  without account usage.

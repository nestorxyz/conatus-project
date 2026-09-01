# ADR 0011: Local supervision, diagnostics, and CI boundary

**Status:** Accepted
**Date:** 2026-09-01
**Depends on:** ADR 0009 and ADR 0010

## Context

F01 and F02 prove the Mac shell, Core, shared contracts, and durable kernel on
one development machine. M1 must not begin until a clean checkout can exercise
those boundaries consistently and a crashing local provider helper cannot
restart forever or leak private provider data into diagnostics.

F03 remains a foundation ticket. It does not select a production Codex version,
enable App Server, install a login item, sign an application, or create a cloud
environment.

## Decision

- Keep the shipped Mac Machine Bridge and Codex Gateway direction in Swift. A
  Node script may orchestrate development verification but is not part of the
  Mac runtime bundle.
- Add a Swift helper supervisor that consumes only a narrow readiness signal,
  reports a bounded restart count, applies a readiness timeout, and stops after
  its configured restart budget. It never returns raw helper output.
- Validate the supervisor with a repository-owned fake-provider executable. The
  fixture may emit deliberately private-looking fields; only a redacted health
  diagnostic crosses the Gateway boundary.
- Gateway diagnostics contain a component, state, version, restart count, and
  allowlisted error code. They contain no credentials, provider references,
  transcript text, workspace paths, or raw process output.
- Development authentication is disabled by default. A production-mode Core
  process rejects any development-auth bypass before binding a listener.
- `check:f03` is the complete local foundation check: F01 contracts and Mac
  build, F02 disposable PostgreSQL migration/failure tests, and the Swift
  helper lifecycle fixture.
- CI uses Node.js 24 and the pinned pnpm version from the repository. Linux runs
  repository quality and disposable PostgreSQL checks; macOS runs Swift/TS
  contract and Gateway lifecycle checks.
- CI runs for pull requests, `main`, and `codex/**` branches so the public
  feature branch is verified before merge.

## Failure behavior

- A helper readiness failure increments the visible restart count.
- A silent helper is terminated when the bounded readiness timeout expires.
- Exhausting the restart budget returns `restart_exhausted`; it does not loop.
- Raw stdout and stderr are discarded after extracting the narrow readiness
  shape and never appear in a diagnostic or Core response.
- A production process with development auth enabled exits before opening its
  HTTP listener.
- A failed migration, cross-language contract, helper lifecycle, dependency,
  secret, or licensing fixture fails its owning CI job.

## Consequences

- The fake-provider fixture proves supervision semantics only. It is not Codex,
  does not validate App Server compatibility, and cannot unblock live execution.
- User-session service installation, signing, update behavior, long-running
  process pressure, sleep/wake recovery, and actual Codex lifecycle remain M1,
  M3, and M5 gates.
- CI success is repository evidence, not production deployment evidence.

## Verification

- The fake helper fails once, restarts once, then reports ready without leaking
  its private-looking provider reference.
- An always-failing helper stops at the configured restart budget.
- production mode rejects development auth while development mode remains
  available only when explicitly enabled.
- The complete F03 check passes from one command and every CI job uses locked
  dependencies and read-only repository permissions.

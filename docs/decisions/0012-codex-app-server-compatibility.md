# ADR 0012: Codex App Server compatibility boundary

**Status:** Accepted for M1 development
**Date:** 2026-09-01
**Depends on:** ADR 0009, ADR 0010, and ADR 0011

## Context

M1 must create and resume Conatus-owned Codex tasks without desktop UI
automation or arbitrary access to a user's existing Codex tasks. The official
Codex App Server protocol provides conversation history, approvals, streamed
events, thread creation/resumption, and version-specific generated schemas.

The installed development candidate is `codex-cli 0.150.1`. Its generated
non-experimental schema bundle is much broader than M1 and changes with the
exact CLI version. Treating every generated method as supported would silently
expand Conatus's authority.

Official references:

- <https://developers.openai.com/codex/app-server>
- <https://developers.openai.com/blog/codex-as-a-platform>

## Decision

- Pin the M1 development candidate to exact CLI version `0.150.1` and the
  SHA-256 digest of its generated non-experimental v2 schema bundle.
- Use local stdio JSONL only. Do not expose App Server through WebSocket, a
  public port, Core, or the Mac UI.
- Initialize once per process connection with `experimentalApi: false` and a
  Conatus client identity.
- Allow only the first M1 compatibility surface: `initialize`, `thread/start`,
  `thread/read`, `thread/resume`, and `turn/start`, plus the lifecycle
  notifications required to observe thread, turn, and item progress.
- M1 development thread creation is always `read-only` with approval policy
  `never`. Effectful execution and provider approval responses remain blocked
  until M3's approval boundary exists.
- Provider thread and turn identifiers never cross the Gateway boundary. Core
  continues to route by Conatus-owned opaque binding IDs.
- Keep the generated schema out of the repository. Regenerate it from the exact
  candidate and compare its digest and allowlisted methods in the compatibility
  check. This keeps the pin reproducible without vendoring unused protocol
  surface.

## Failure behavior

- A missing binary, version mismatch, schema digest mismatch, or missing
  allowlisted method fails the M1 compatibility check.
- Experimental capability negotiation is rejected by the Swift request model.
- Thread creation cannot express workspace-write, danger-full-access, or a
  permissive approval policy through this boundary.
- Unknown notifications are retained only as redacted observations in later
  adapters and cannot mutate Conatus lifecycle state.

## Consequences

- This pin validates one installed development candidate; it is not a signed
  release dependency or proof of commercial distribution entitlement.
- A Codex upgrade requires an explicit manifest update, regenerated schema
  digest, compatibility review, and repeated lifecycle fixtures.
- Real account-backed thread creation remains a separate M1 validation because
  it persists provider state and consumes Codex usage.

## Verification

- Generate the non-experimental JSON Schema with the pinned candidate and match
  the exact bundle digest.
- Prove every allowlisted request and notification exists in that generated
  schema and experimental API is absent from Conatus request fixtures.
- Swift independently emits exact initialize, read-only thread-start,
  thread-read, thread-resume, and turn-start JSON shapes.

# ADR 0019: Account voice grants and quota

**Status:** Accepted for M2-03
**Date:** 2026-09-02
**Depends on:** ADR 0010, ADR 0016, and ADR 0017

## Context

The Mac needs temporary authority to send only post-wake command audio through
the Conatus-managed transcription path. Giving the Mac a provider credential,
trusting client-selected account scope, or checking quota outside the durable
admission transaction would make cost, revocation, and cross-account isolation
unreliable.

## Decision

- Core issues an opaque Conatus relay token only after loopback and account
  authentication. Account and principal scope come from server identity, never
  request data.
- The token authorizes only `transcribe_post_wake_audio`. It contains no
  provider name or credential and expires after five minutes.
- A grant reserves bounded audio milliseconds and turns atomically against a
  UTC account-day ledger. The first policy is one active grant per account,
  60 minutes of audio per UTC day, at most five minutes and ten turns per grant.
- Core stores only SHA-256 of the relay token. The plaintext token is returned
  once and is never placed in events, outbox records, logs, public status, or
  normal reads.
- Relay admission atomically verifies the token, account, principal, active
  state, expiry, turn count, and remaining reserved audio before moving reserved
  quota to consumed quota. A failed admission changes nothing.
- Revocation and expiry release unused reservation. Expired abandoned grants
  are reclaimed before issue/admission and by an explicit cleanup operation.
- Grant issue, use, revoke, expire, and exhaust transitions are durable. Their
  events contain IDs, state, and numeric usage only—not token hashes, plaintext
  tokens, transcripts, audio, provider data, or paths.

## Consequences

- M2-04 can attach a provider adapter behind a Conatus relay without changing
  Mac authentication or exposing the provider credential.
- Reserving quota makes concurrent issue deterministic but can temporarily
  reduce available quota until an abandoned grant expires or cleanup runs.
- The initial limits are launch defaults, not billing-plan promises. Future
  account plans may configure them without changing grant semantics.

## Verification

- Unknown fields, client account/principal selection, non-loopback requests,
  malformed allowances, and unauthenticated issue/revoke fail closed.
- Concurrent issue cannot exceed the active-grant or daily reservation limits.
- Cross-account and cross-principal token use fail without revealing whether a
  grant exists.
- Expiry and revocation release unused reservation exactly once; replayed
  cleanup is idempotent.
- Relay usage cannot exceed reserved audio or turns, and exhausted grants cannot
  be reused.
- HTTP responses and durable evidence contain no provider credential, provider
  identifier, token hash, transcript, audio, path, or raw output.

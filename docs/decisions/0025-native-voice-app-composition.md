# ADR 0025: Native voice app composition

**Status:** Accepted for M2-06d
**Date:** 2026-09-02
**Depends on:** ADR 0018, ADR 0021, ADR 0022, ADR 0023, and ADR 0024

## Context

Conatus has independently verified native capture, account transcription,
named Task routing, private presentation, and speech boundaries. The Mac still
needs one composition root that connects those boundaries without making normal
startup claim that unavailable launch capabilities are ready.

## Decision

- `VoiceApplicationComposition` constructs one main-actor conversation graph:
  capture, granted account transcription, provider-neutral relay events, named
  Task routing, private in-memory presentation, and native speech.
- Relay events cross a serialized bridge into the coordinator. Transport errors
  become the coordinator's bounded failure vocabulary; raw provider errors do
  not enter presentation or public state.
- `VoicePresentationStore` owns only current-process UI state. It does not log or
  persist partials, committed transcripts, provider data, credentials, paths, or
  Codex identities.
- Normal Mac startup evaluates account session, verified wake model, and account
  transcription relay availability before constructing or arming live voice.
  Missing capabilities are visible, voice stays `off`, and startup does not
  request microphone access.
- The current build intentionally reports the wake model and relay unavailable.
  A development account token alone cannot make the launch path ready.
- M2-06d verification injects synthetic audio and fake external boundaries. It
  makes no microphone, provider, production account, or Codex execution call.

## Consequences

- The complete native state and recovery journey can be tested through the same
  composition boundary that a future live launch path will use.
- Capability readiness cannot be inferred from a credential-like environment
  value or from individual drivers merely existing in the package.
- The Mac UI can explain why voice is unavailable without exposing private
  routing or provider details.
- M2-06e remains responsible for the separately approved live model, microphone,
  account relay, transcription, Task dispatch, speech, and hardware evidence.

## Verification

- A synthetic journey proves wake/capture, partial/final transcription, matching
  named Task admission, private commit, spoken status, and follow-up capture.
- Recovery tests prove a network-cancelled turn cannot route and a replacement
  turn can complete safely.
- Failure tests prove grant denial becomes a visible recoverable quota failure.
- Startup tests prove missing capabilities remain visible and voice remains off.
- Static checks exclude Apple Speech recognition, provider credentials and
  endpoints, microphone authorization, and direct microphone construction from
  the composition and normal startup path.

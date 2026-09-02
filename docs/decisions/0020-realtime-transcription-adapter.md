# ADR 0020: Provider-neutral Realtime transcription adapter

**Status:** Accepted for M2-04
**Date:** 2026-09-02
**Depends on:** ADR 0017 and ADR 0019

## Context

Conatus needs low-latency post-wake transcription without binding product voice
semantics to one provider's event names or identifiers. The provider can emit
partial and completed transcripts for different committed turns out of order.
Raw provider messages are untrusted input and may be malformed, duplicated, or
delayed.

The official OpenAI Realtime transcription guide retrieved on 2026-09-02 uses
`gpt-live-transcribe`, 24 kHz PCM, explicit `input_audio_buffer.commit`, delta
and completed events, and `item_id` to reconcile committed turns:
<https://developers.openai.com/api/docs/guides/realtime-transcription>.

## Decision

- Core exposes a provider-neutral transcription session whose outputs contain
  only a Conatus Voice Turn ID, local revision, partial/final text, or a typed
  safe failure. Provider item/event identifiers stay inside the adapter.
- The first provider codec pins `/v1/realtime/transcription_sessions`,
  `gpt-live-transcribe`, mono PCM16 at 24 kHz, low delay, and explicit turn
  commits with provider turn detection disabled.
- Audio chunks are non-empty, even-byte PCM16, sequential, bounded to one second
  each, and bounded to five minutes per turn. A gap, duplicate sequence, wrong
  turn, empty commit, or overlapping unbound commit fails locally.
- Provider commit acknowledgements bind provider item IDs to pending Conatus
  Voice Turn IDs. Delta order is preserved per item; the completed transcript
  is authoritative. Completion order across turns does not determine routing.
- Duplicate provider events and any delta/final after a terminal result cannot
  produce another final. An empty completed transcript becomes a typed
  recoverable failure rather than a command.
- Known malformed mapped events, unknown item references, and impossible commit
  acknowledgements fail the session closed without returning raw provider data.
  Provider errors and disconnects become typed recoverable failures.
- Provider authentication and the real network transport remain behind the
  Relay boundary. M2-04 includes only a deterministic in-memory transport and
  performs no provider call, microphone capture, quota spend, or transcript
  persistence.

## Consequences

- M2-05 can render partial text and route exactly one final by Voice Turn ID
  without understanding provider event names.
- One commit may await its provider item acknowledgement at a time. Completed
  items may remain in flight concurrently and finish in any order.
- A future provider replaces the codec/transport without changing Conatus turn
  lifecycle or command-routing semantics.
- The real authenticated transport and one bounded live transcription remain a
  separately approved validation; fake success is not production evidence.

## Verification

- The first outbound message is the exact pinned transcription-only session
  update and contains no credential.
- Ordered PCM append/commit messages are deterministic and malformed audio fails
  before transport mutation.
- Two bound turns completing out of order produce finals for the correct
  Conatus Voice Turn IDs.
- Duplicate finals, late deltas, unknown items, empty finals, send failures, and
  disconnects produce at most one terminal provider-neutral result per turn.
- Fake-transport tests use synthetic byte arrays only and make no network call.

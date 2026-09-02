# ADR 0023: Authenticated account-transcription transport

**Status:** Accepted for M2-06b
**Date:** 2026-09-02
**Depends on:** ADR 0019, ADR 0020, ADR 0021, and ADR 0022

## Context

The native conversation coordinator has only an abstract account-transcription
dependency. The Mac must obtain temporary Conatus authority and deliver only a
captured Voice Turn without receiving an OpenAI key, provider session identity,
or account scope selected by the client. A deterministic fake relay must prove
this boundary before any live provider use is considered evidence.

The official OpenAI Realtime transcription guide retrieved on 2026-09-02 uses
24 kHz PCM, explicit audio append/commit, transcript deltas, and a completed
transcript for each committed item:
<https://developers.openai.com/api/docs/guides/realtime-transcription>.

## Decision

- The Mac requests a versioned grant over authenticated loopback HTTP. The body
  contains only requested milliseconds and turns; account and principal remain
  server-derived. Only loopback `http` endpoints are accepted.
- The response is decoded with an exact-field contract shared with TypeScript.
  It accepts one unexpired opaque Conatus relay token scoped only to
  `transcribe_post_wake_audio`; provider fields and unknown fields fail closed.
- The relay token remains in memory for one active Voice Turn. It is passed only
  to the injected Conatus relay boundary, revoked on final, failure, cancellation,
  insufficient allowance, or relay-start failure, and never enters presentation,
  persistence, public status, or telemetry.
- Captured finite mono Float32 samples are bounded to five minutes, normalized
  to mono PCM16 at 24 kHz, and split into chunks of at most one second before
  crossing the relay boundary. The current deterministic converter makes no
  network or microphone call; representative-device audio quality remains a
  live-acceptance gate.
- Relay events contain only Voice Turn ID, monotonic local revision, safe
  partial/final text, or typed recoverability. A revision gap, empty or oversized
  text, wrong or late turn, duplicate terminal, or event after cancellation
  fails closed and cannot revive the grant.
- M2-06b verification uses an injected fake relay and synthetic samples. It
  performs no microphone access, OpenAI connection, provider authentication,
  paid usage, transcript persistence, or Task dispatch.

## Consequences

- M2-06d can compose the account transcriber with the M2-05 coordinator without
  placing account or provider authority in the UI.
- A real relay implementation can replace the fake behind the same interface;
  the first bounded live provider run remains M2-06e and requires explicit
  approval.
- The converter's quality must be measured with representative microphones,
  accents, background noise, and code-switching before live launch acceptance;
  deterministic byte-shape tests are not accuracy evidence.

## Verification

- Shared vectors prove Swift and TypeScript accept the same strict grant and
  reject provider or unknown fields.
- A URL-protocol test proves authenticated POST and DELETE requests stay on the
  loopback grant route and never include account or provider scope in the body.
- Fake-relay tests prove bounded grant sizing, 24 kHz PCM16 one-second chunks,
  partial/final forwarding, terminal revocation, cancellation, late-event
  suppression, insufficient allowance denial, and revision-gap failure.
- Focused checks statically exclude OpenAI/provider endpoints, provider keys,
  Apple Speech recognition, transcript persistence, and client-selected account
  identifiers from the native transport.

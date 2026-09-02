# ADR 0017: Account-managed voice lifecycle on Mac

**Status:** Accepted for M2
**Date:** 2026-09-02
**Depends on:** ADR 0007, ADR 0009, and ADR 0016

## Context

Conatus must be usable when the developer cannot touch the Mac. A shortcut,
push-to-talk button, or pause after the wake phrase does not satisfy that job.
The existing Apple Speech prototype also produced transcription quality below
the intended product experience and required a user-owned provider key.

OpenAI's current Realtime transcription guide recommends
`gpt-live-transcribe` for incremental microphone transcription, identifies
24 kHz PCM as an input format, emits delta and completed transcript events, and
requires `item_id` reconciliation because completion order across turns is not
guaranteed:

- <https://developers.openai.com/api/docs/guides/realtime-transcription>

Those provider details can change. Conatus therefore needs a product-owned
voice lifecycle and a replaceable transcription adapter.

## Decision

- The launch interaction is hands-free: local detection of the phrase
  `Hey Conatus` arms one post-wake capture without a button or required pause.
  The words following the wake phrase in the same utterance belong to that
  capture.
- Wake detection remains local and replaceable. Pre-wake audio is never sent to
  Core or a transcription provider. The chosen detector/model must have terms
  suitable for open-source commercial distribution; third-party weights with
  noncommercial restrictions are not shippable dependencies.
- Detection produces immediate audible and visible acknowledgement before the
  command is represented as accepted. Feedback is part of the state machine,
  not optional decoration.
- Post-wake command audio uses account-managed cloud transcription. The Conatus
  account owns authorization, quota, and provider cost. Users do not supply or
  store an OpenAI API key, and the Mac never receives a long-lived provider
  credential.
- The production command-transcription path does not use Apple Speech. Local
  wake classification and local voice-activity/turn capture remain allowed and
  are separate from semantic transcription.
- `WakeDetector`, `TurnCapture`, `Transcriber`, and `SpeechOutput` are narrow,
  replaceable Mac boundaries. Core owns account policy and grants; the Mac owns
  microphone and audio-route interaction; the Gateway owns Codex execution.
- A final transcript is routed at most once by its provider-neutral Voice Turn
  ID. Partial deltas are presentation only and never dispatch work. Provider
  event identifiers remain inside the transcription adapter.
- After Conatus speaks a result, a bounded active-conversation window accepts a
  follow-up without repeating the wake phrase. Speaking during output performs
  barge-in: output stops immediately and the new capture becomes visibly live.
- Raw microphone audio is not persisted by default. Public status, telemetry,
  notifications, and crash diagnostics contain no audio, transcript, provider
  identifier, credential, or repository content. A final transcript may enter
  the authenticated command history only when the user-visible turn commits.

## Lifecycle

```text
off -> armed -> acknowledging -> capturing -> transcribing -> routing
                                              |              |
                                              v              v
                                          recovering      working
                                                             |
                                                             v
                                                          speaking
                                                             |
                                      follow-up window -------+----> armed
                                                             |
                                                           barge-in
                                                             v
                                                          capturing
```

`blocked` is terminal until an explicit recovery action. Network loss before a
final transcript produces `recovering`; it cannot fabricate acceptance or
offer a duplicating dispatch.

## Failure behavior

- A false wake or explicit cancellation returns to `armed` without routing.
- Empty, delayed, truncated, malformed, duplicated, or out-of-order transcript
  events do not dispatch a command.
- A duplicate final event for the same Voice Turn ID is ignored after the first
  accepted route action.
- Microphone denial, unsupported audio route, account/quota rejection, expired
  grant, provider outage, and uncertain command admission remain distinct typed
  failures at their owning boundary before mapping to safe public status.
- Losing connectivity after command admission does not relabel the command
  unsent; M1 idempotency and later M3 recovery reconcile the authoritative Task.

## Consequences

- M2 can test the complete experience against fakes before requesting
  microphone access or spending provider quota.
- Conatus can replace the transcription provider without changing wake,
  conversation, routing, or Codex semantics.
- Account-managed voice requires a short-lived grant/relay design, quota and
  abuse controls, and cross-account negative tests before a live transcription
  validation.

## Verification

- TypeScript and Swift accept the same transcript-free public voice-status
  vectors and reject private or unknown fields.
- A deterministic Swift state machine proves same-utterance activation,
  acknowledgement, partial/final separation, one route per Voice Turn ID,
  continuous follow-up, barge-in, cancellation, and network recovery.
- Encoded public status exposes no raw audio, transcript, provider
  identifier, credential, path, or Codex reference.
- Live microphone and provider tests remain separately approval-gated tickets.

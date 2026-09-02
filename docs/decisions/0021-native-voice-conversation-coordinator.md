# ADR 0021: Native voice conversation coordinator

**Status:** Accepted for M2-05
**Date:** 2026-09-02
**Depends on:** ADR 0016, ADR 0017, ADR 0019, and ADR 0020

## Context

The managed voice lifecycle, local audio boundary, account grants, and
provider-neutral transcription adapter already exist as separate contracts.
The Mac still needs one integration owner that preserves those boundaries while
turning an admitted final transcript into exactly one Task command and keeping
partial text, spoken output, cancellation, and recovery coherent.

## Decision

- A `@MainActor` native coordinator owns integration of capture, account-backed
  transcription, Task routing, speech output, and private presentation.
- Each dependency is a narrow injected protocol. The coordinator receives no
  provider credential, raw App Server API, repository path, or Apple Speech
  capability.
- Wake acknowledgement and local capture start before account transcription.
  Only a captured `VoiceTurnID` can begin transcription.
- Partial transcript deltas are bounded, private presentation state. Only one
  non-empty final can cross the Task-routing boundary, and the UI commits it
  only after routing returns a matching Voice Turn ID and non-empty command ID.
- Spoken completion chooses either an explicit follow-up capture or a return to
  wake-required mode. Barge-in stops speech before starting follow-up capture.
- Cancellation is valid during capture, transcription, routing, work, spoken
  output, and recovery. Late events for a cancelled or admitted turn cannot
  route again.
- Network loss, input-route loss, sleep/wake, dependency failures, malformed
  receipts, and invalid lifecycle events are visible typed outcomes. Invalid
  lifecycle events fail closed instead of being silently ignored.
- Public status remains the transcript-free projection from ADR 0017. Private
  partial and committed transcript presentation is authenticated UI state and
  is not written to disk by this coordinator.

## Consequences

- Native lifecycle behavior can be tested end to end with fakes while real
  microphone, provider transport, production routing, and paid use remain
  separately gated.
- Production drivers can replace the fakes without changing the lifecycle or
  routing semantics.
- M2-05 is integration-contract evidence, not live voice-product evidence.

## Verification

- Five wake-required commands, one conversation-start command, and two
  follow-ups route under eight distinct Voice Turn IDs exactly once.
- Tests cover acknowledgement-before-transcription, presentation-only partials,
  receipt validation, barge-in order, cancellation during transcription and
  speech, network/audio-route recovery, sleep/wake, quota denial, invalid
  lifecycle failure, and transcript-free public status.
- The focused gate uses fake dependencies and synthetic samples only; it makes
  no microphone, network, provider, persistent transcript, or Codex task call.

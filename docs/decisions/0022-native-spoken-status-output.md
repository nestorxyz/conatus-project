# ADR 0022: Native spoken-status output

**Status:** Accepted for M2-06a
**Date:** 2026-09-02
**Depends on:** ADR 0017 and ADR 0021

## Context

M2-05 defines a replaceable `SpeechOutput` boundary but verifies it only with a
fake. Conatus needs immediate acknowledgement, useful spoken status, and
barge-in cancellation without adding another network service or conflating
speech synthesis with command transcription.

## Decision

- The first production `SpeechOutput` driver uses macOS `AVSpeechSynthesizer`.
  This is local text-to-speech only; Apple Speech recognition remains excluded
  from command transcription.
- A short system acknowledgement sound remains separate from spoken status so
  wake feedback can begin immediately.
- Spoken status is trimmed, non-empty, and bounded to 1,000 characters before
  entering the native synthesizer. The driver accepts one utterance at a time.
- Completion is asynchronous and resolves only when native speech finishes.
  Cancellation or barge-in stops output immediately and resolves the pending
  operation as cancelled exactly once.
- The driver receives only the already-approved user-facing status string. It
  has no transcript, provider, credential, path, Task-routing, persistence, or
  network capability.
- The native backend remains behind the existing `VoiceSpeechControlling`
  protocol and may be replaced without changing conversation semantics.

## Consequences

- Spoken status and interruption can ship without provider cost or connectivity.
- Voice quality follows the selected macOS system voice until Conatus chooses a
  different replaceable output driver.
- M2-06a does not make Conatus hands-free: wake-model, capture, authenticated
  transcription, Task routing, and live composition remain later gates.

## Verification

- Fake-backend tests prove normalization, length rejection, one active utterance,
  successful completion, native failure, cancellation, barge-in stop, and
  exactly-once continuation resolution.
- Static checks exclude Apple Speech recognition, network, persistence,
  credentials, and transcript ownership from the driver.
- Tests never play audio or change the user's selected system voice.

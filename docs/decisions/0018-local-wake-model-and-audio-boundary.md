# ADR 0018: Native local wake model and activated-audio boundary

**Status:** Accepted for M2-02
**Date:** 2026-09-02
**Depends on:** ADR 0009 and ADR 0017

## Context

M2 needs literal hands-free activation without sending ambient audio to a
service or using Apple Speech for command transcription. A wake engine and the
weights it runs have separate licensing and provenance risks.

The openWakeWord repository licenses its code under Apache-2.0, but explicitly
licenses its included pretrained models under CC BY-NC-SA 4.0. Those weights
cannot be a Conatus launch dependency. sherpa-onnx provides a native keyword-
spotting runtime, but the redistribution license for the evaluated official KWS
weights is not explicit enough to pass the repository's distribution gate.

Apple Sound Analysis supports live audio streams and custom Core ML sound
classification models. Create ML can train a sound classifier from owned audio
examples and a negative class:

- <https://developer.apple.com/documentation/soundanalysis/>
- <https://developer.apple.com/documentation/createml/mlsoundclassifier/>
- <https://github.com/dscripka/openWakeWord>
- <https://github.com/k2-fsa/sherpa-onnx/issues/3760>

## Decision

- The Mac V1 wake runtime uses Apple's on-device Sound Analysis framework with
  a Conatus-owned custom Core ML model. Sound Analysis performs acoustic
  classification only; Apple Speech remains outside the production command-
  transcription path.
- The runtime remains behind a `WakeDetector` boundary. A future detector may
  replace Sound Analysis only when its code, weights, runtime support, latency,
  and commercial redistribution rights pass the same gate.
- No third-party pretrained wake weights ship in Conatus. A Conatus wake model
  may be bundled only with a manifest recording every training-data source and
  license, model license, training recipe, model digest, labels, supported audio
  format, evaluation corpus, false accepts, false rejects, accent coverage, and
  tested Mac hardware.
- Local audio is represented by monotonically ordered sample-frame positions.
  A bounded rolling buffer keeps audio only in memory. When a detector produces
  a local activation range, capture may retain the recognized wake phrase and
  subsequent command from that range; samples before the activation range are
  excluded from the committed activated turn and can never reach transcription.
- Activation emits audible and visible feedback immediately, before a cloud
  grant or transcription session exists. Feedback failure is visible but does
  not silently invent command acceptance.
- Local energy-based turn-end detection may delimit the activated utterance. It
  does not infer command meaning and is replaceable independently of the wake
  model and cloud transcriber.
- Raw audio is not written to disk by default. Dataset collection, diagnostic
  capture, and model evaluation require a separate explicit consent flow and
  are not enabled by the product runtime.

## M2-02 delivery boundary

M2-02 is split at the evidence boundary:

1. **M2-02a local audio kernel:** audio contracts, bounded rolling memory,
   activation-range isolation, wake-score gating, turn-end detection, immediate
   feedback actions, and deterministic fault/privacy tests.
2. **M2-02b1 native adapter boundary:** strict model-provenance manifest and
   digest verification, microphone permission/lifecycle, copied monotonic audio
   frames, and serialized Sound Analysis scoring without a bundled model or live
   microphone start.
3. **M2-02b2a owned-data and training boundary:** strict consent, license,
   clip-digest, audio-format, split-isolation, held-out-subject, offline
   evaluation, and Create ML export tooling. It contains no recorder, dataset,
   or model weights.
4. **M2-02b2b candidate model:** separately consented recordings outside the
   repository, approved launch-quality corpus thresholds, a trained candidate,
   offline false-accept/false-reject evidence, and a digest-verified runtime
   manifest.
5. **M2-02b2c hardware validation:** bundled candidate plus live same-sentence,
   feedback-latency, false-wake, false-reject, accent, sleep/wake, permission,
   repeated lifecycle, and headset-route evidence on supported Macs.

M2-02a does not request microphone permission, include a model, start an audio
engine, or claim that the Mac can hear the wake phrase. M2-02b1 includes the
permission declaration and adapter code but does not request access at test or
application startup. M2-02b2a does not record, download, or synthesize audio and
does not train placeholder weights. M2-02 is complete only after M2-02b2c passes
on supported hardware.

## Consequences

- Conatus avoids a paid wake-word service and does not depend on noncommercial
  or ambiguous model weights.
- The deterministic audio kernel can be verified before microphone permissions
  or personal voice data enter scope.
- Building a launch-quality custom wake model becomes real product work rather
  than an implicit dependency download.

## Verification

- The rolling buffer never exceeds its configured frame capacity and rejects
  gaps, overlap, sample-rate drift, malformed scores, and invalid ranges.
- A committed activated turn starts exactly at the accepted activation range;
  earlier ambient samples are absent.
- Consecutive-score and cooldown rules emit one activation rather than repeated
  triggers.
- Turn-end detection requires post-activation speech, closes on bounded trailing
  silence, and enforces a maximum duration.
- Encoded diagnostics contain counts and safe state only, never sample values,
  audio bytes, paths, model internals, or transcripts.
- M2-02b1 rejects incomplete, unknown, noncommercial, filename-drifted, and
  digest-mismatched model manifests before any Core ML compilation boundary.
- Synthetic native buffers prove deep-copy isolation, first-channel sample
  projection, monotonic frame positions, permission denial before input-node
  access, and deterministic Sound Analysis result mapping.
- Sound Analysis work is serialized away from the real-time audio callback. The
  built app declares its scoped microphone purpose, while tests and normal
  startup neither request permission nor start capture.
- M2-02b2a validates external audio against a strict manifest, approved
  commercial-license identifiers, consent references, immutable clip digests,
  mono 16 kHz-or-higher metadata, recording-session split isolation, and a wake
  subject held out from training. Create ML consumes a private digest-verified
  snapshot, not mutable source paths.
- The offline trainer fixes validation data and training parameters, evaluates
  only the held-out test corpus, counts background-window false accepts and
  wake-clip false rejects, exports a candidate model plus strict runtime
  manifest atomically, and contains no microphone or recording API.

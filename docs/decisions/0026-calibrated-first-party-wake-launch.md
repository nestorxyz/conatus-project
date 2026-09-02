# ADR 0026: Calibrated first-party wake launch

**Status:** Accepted for the next M2 task
**Date:** 2026-09-02
**Supersedes:** ADR 0018 only where it made the 48-speaker corpus a prerequisite
for the first calibrated Mac launch
**Depends on:** ADR 0018 and ADR 0025

## Context

ADR 0018 correctly selected local Sound Analysis with a Conatus-owned Core ML
model and rejected paid wake services and noncommercial pretrained weights. The
first collection packet then defined a broad 48-speaker launch corpus. That is
useful expansion evidence, but making it a prerequisite would delay a narrowly
supported Mac release even when each user can calibrate activation locally.

openWakeWord demonstrates a useful training pattern: synthetic positive speech,
augmentation, hard negative phrases, and a small wake classifier. Its code is
Apache-2.0, while its included pretrained models are CC BY-NC-SA-4.0 and cannot
ship in Conatus. The commercial status of shared pretrained feature weights also
requires clarification. Conatus therefore adopts the method as prior art, not
its bundled weights or an unreviewed runtime dependency.

## Decision

- Mac V1 keeps the existing native runtime: Sound Analysis executes a
  digest-verified Conatus Core ML classifier entirely on-device.
- The initial candidate may use commercially reviewed synthetic pronunciations,
  augmentation, hard negatives, and separately consented human validation.
  Every generator, dataset, feature model, and derived artifact must pass the
  existing provenance and redistribution gate.
- No openWakeWord pretrained wake model or ambiguously licensed shared feature
  weight ships. Conatus owns and licenses the final classifier weights.
- Initial support is deliberately narrow: Apple Silicon, macOS 14 or later,
  built-in microphones, quiet or ordinary indoor rooms, approximately 0.5–2 m
  range, and the exact `Hey Conatus` phrase. Initial pronunciation evaluation
  targets `es-PE` and `en-US`; it does not imply support for every speaker in
  either language.
- Onboarding locally records a small calibration challenge. It selects a
  device/user threshold; it does not grant identity authority or retrain a
  cloud model. Raw calibration audio is deleted after the challenge unless the
  user separately opts into a reviewed improvement program.
- Wake activation remains disabled when the calibration challenge cannot meet
  the product's false-accept and false-reject gate. A visible manual activation
  remains available instead of claiming unsupported hands-free readiness.
- The 48-speaker, 24-hour negative corpus remains the broader expansion gate. It
  is not erased or presented as completed, but it no longer blocks the first
  calibrated and honestly scoped Mac launch.

## Next task

M2-02b2b2a defines and implements the synthetic candidate and local calibration
contract before any personal recording or live microphone validation. It must:

1. Record exact commercial provenance for every synthetic generator, source
   corpus, feature extractor, augmentation input, and output weight.
2. Add hard-negative phrases and a fixed held-out evaluation corpus.
3. Extend the runtime manifest with the declared hardware, microphone,
   environment, distance, phrase, pronunciation, and calibration scope.
4. Implement a local calibration state machine using synthetic score/audio
   fixtures first, including pass, fail, retry, deletion, and manual-fallback
   outcomes.
5. Produce no microphone recording, provider request, downloaded model,
   generated audio, or trained candidate without the separately required
   approvals and evidence.

## Consequences

- The initial launch claim becomes “calibrated for this user and supported Mac,”
  not universal wake-word recognition.
- Conatus preserves local activation, model ownership, and freedom from a
  recurring wake-service fee.
- Synthetic generation reduces initial human collection but does not replace
  consented human and live household validation.
- Broader accents, rooms, distances, headsets, and hardware become measured
  expansion work rather than implied launch support.

## Verification

- Static gates reject noncommercial or unreviewed model components and any
  manifest that omits the declared support scope.
- Deterministic calibration tests prove audio stays local, raw calibration state
  is deleted, thresholds cannot authorize commands, and failed calibration
  leaves wake activation off with a visible manual fallback.
- M2-02b2c still requires explicit live microphone approval and supported-Mac
  evidence before M2-06e can claim the complete voice experience.

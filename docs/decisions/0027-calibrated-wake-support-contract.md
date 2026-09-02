# ADR 0027: Calibrated wake support contract

**Status:** Accepted
**Date:** 2026-09-02
**Depends on:** ADR 0018 and ADR 0026

## Context

The first calibrated Mac launch needs a machine-checkable boundary between a
model artifact, its honest support claim, and the threshold selected on one
device. A successful offline score must not silently imply support for another
Mac, microphone, room, distance, phrase, or pronunciation. Calibration also
must not become an identity or command-authority mechanism.

## Decision

- Runtime wake manifests use schema version 2 and fail closed unless they bind
  exact model bytes to the initial `arm64`, macOS 14+, built-in microphone,
  quiet/ordinary indoor, 0.5–2 m, exact `Hey Conatus`, `es-PE`/`en-US` scope.
- Every manifest carries a versioned, expiring calibration policy. Candidate
  thresholds are ordered and unique. The local calibrator chooses the lowest
  candidate satisfying both false-reject and hard-negative false-accept limits.
- Calibration stores only scores while running. Every accepted or rejected
  trial produces a raw-audio deletion effect before any enable-wake effect.
  The platform integration remains responsible for executing and verifying
  that deletion; fixture tests are not evidence of filesystem deletion.
- A reusable receipt binds the selected threshold to the opaque device ID,
  exact model SHA-256, and policy revision. Expiry, device/model/policy drift,
  unsupported hardware, malformed sequence, or failed scores disable wake and
  expose manual activation.
- A calibration threshold authorizes only wake activation. It cannot identify
  a person, choose a Task, admit a command, or satisfy an approval.
- Synthetic generation, actual audio, model training/download, microphone use,
  and live hardware validation remain outside this ticket.

## Consequences

- The launch support claim is executable and narrow rather than marketing text.
- Updating a model or calibration policy requires calibration again.
- The deterministic fixture suite can validate state-machine safety before any
  personal audio exists.
- M2-02b2c must integrate the verified candidate, execute deletion against real
  ephemeral capture, and collect supported-Mac evidence under explicit approval.

## Verification

- Strict JSON tests reject omitted, unknown, or expanded support claims.
- Pure Swift tests cover pass, score failure, retry, deletion ordering, stale
  policy, stored-receipt mismatch, unsupported hardware, and manual fallback.
- The M2-02b2b2a gate rejects committed audio/model assets and microphone,
  provider, persistence, download, and model-training capability in the new
  calibration boundary.

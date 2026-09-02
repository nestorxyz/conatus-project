# Calibrated `Hey Conatus` launch packet

This packet fixes the first synthetic-candidate inputs and the evidence required
before any generator, audio, feature weight, or trained output is accepted. It
does not authorize or claim that generation or training occurred.

## Provenance admission matrix

Each future candidate manifest and its external build record must identify all
of these components with immutable content SHA-256, exact version, SPDX license
or reviewed terms reference, commercial-use and redistribution decisions,
reviewer reference, input lineage, and output lineage:

| Component role | Initial plan | Admission state |
|---|---|---|
| Synthetic speech generator and each voice | Local or contractually approved generator selected after terms review | Blocked until reviewed |
| Source text corpus | The fixed phrase sets below, authored by Conatus | Admitted as repository text |
| Background/noise corpus | Separately licensed source with item-level hashes | Blocked until reviewed |
| Feature extractor and weights | Apple Create ML Audio Feature Print or separately reviewed Conatus-owned alternative | Blocked until SDK/redistribution review is recorded |
| Augmentation implementation and impulse/noise inputs | Deterministic, version-pinned recipe with every external input licensed | Blocked until reviewed |
| Classifier and output weights | Conatus-owned classifier; exact recipe and output hashes | Blocked until an approved run |

No openWakeWord pretrained classifier or ambiguously licensed shared feature
weight is an admissible shortcut. A component marked blocked cannot be replaced
by a URL, package name, or a statement that it is “open source.”

## Fixed phrase sets

Positive text is exactly `Hey Conatus`, rendered only for the declared `es-PE`
and `en-US` pronunciation targets. The first hard-negative text set is:

1. `Conatus`
2. `Okay Conatus`
3. `Hey Donatus`
4. `Hey go Natus`
5. `Hey computer`
6. `Hey contacts`
7. `Hey can you`
8. `Hey Jonathan`
9. `Hey bananas`
10. `Are you listening?`

Ordinary speech and non-speech background are separate negative classes; this
list does not substitute for the preserved 24-hour negative expansion gate.

## Fixed fixture evaluation

Before real audio exists, state-machine behavior is fixed by six ordered score
fixtures per run: three positive trials followed by three hard negatives.
The launch policy candidates are `0.55`, `0.65`, and `0.75`, with zero allowed
false rejects and zero allowed hard-negative false accepts.

- Passing fixture: positives `0.82, 0.76, 0.71`; negatives `0.18, 0.31, 0.54`.
  It must select `0.55`.
- Failing fixture: positives `0.30, 0.30, 0.30`; negatives
  `0.80, 0.80, 0.80`. It must disable wake and expose manual activation.
- Drift fixtures: expired policy, another opaque device ID, another model hash,
  another policy revision, unsupported architecture, and out-of-order trial.
  Every case must fail closed.

Real held-out audio will receive a separate immutable corpus manifest and hash.
These numeric fixtures test deterministic control flow, not acoustic accuracy.

## Runtime and deletion boundary

The verified runtime manifest is the sole source for model digest, support
scope, and calibration policy. The local state machine retains scores only and
emits opaque capture-deletion effects. A platform adapter must delete ephemeral
raw audio before enabling wake and must never interpret calibration as identity,
Task selection, command admission, or approval. Real deletion and live wake
quality remain M2-02b2c evidence.

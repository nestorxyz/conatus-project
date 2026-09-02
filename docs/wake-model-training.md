# `Hey Conatus` model production

This workflow produces a Conatus-owned Core ML wake-model candidate without
placing personal audio, licensed datasets, or generated weights in Git. It is an
offline development tool, not part of the Conatus Mac runtime.

Apple recommends gathering representative positive audio plus a negative class,
using at least ten examples per category, mono audio at 16 kHz or higher, and
separate training, validation, and testing evidence. Conatus treats those as a
minimum tooling gate rather than launch-quality proof:

- <https://developer.apple.com/documentation/createml/mlsoundclassifier/>
- <https://developer.apple.com/documentation/createml/mlsoundclassifier/datasource>
- <https://developer.apple.com/documentation/createml/improving-your-model-s-accuracy>

## Privacy and consent boundary

- Keep the dataset and output directories outside this repository. `wake-data/`
  and `wake-model-output/` are ignored only as an additional local safeguard.
- Do not record anyone until the collection script, consent language, permitted
  uses, retention/deletion process, compensation if applicable, and launch
  corpus thresholds have been reviewed and explicitly approved.
- Use opaque `sourceID`, `subjectID`, `consentReference`, `clipID`, and
  `recordingSessionID` values. Do not put names, email addresses, account IDs,
  or consent documents in the manifest.
- M2-02b2a includes no recorder. It never requests microphone access and never
  downloads or synthesizes examples.

## Dataset manifest

The strict JSON root contains exactly:

- `schemaVersion`: `1`.
- `datasetID`: an opaque immutable dataset revision.
- `distributionApprovalReference`: an opaque pointer to the reviewed approval.
- `sources`: exact `sourceID`, `subjectID`, `licenseIdentifier`,
  `consentReference`, and `accentTags` records.
- `clips`: exact `clipID`, `relativePath`, `sha256`, `sourceID`,
  `recordingSessionID`, `label`, `split`, `sampleRate`, `channelCount`, and
  `durationMilliseconds` records.

Labels are `hey_conatus` and `background`; splits are `training`, `validation`,
and `testing`. The validator requires at least ten training clips and one
validation/test clip for each label, at least 60 minutes of held-out background,
mono audio at one consistent sample rate of 16 kHz or higher, no recording
session across splits, and at least one held-out wake subject not used for
training. M2-02b2b1 adopts stronger launch thresholds before collection;
M2-02b2b2 owns the separately approved collection and candidate run.

Approved license identifiers are deliberately allowlisted in code. Adding one
requires review rather than changing a manifest string.

## Commands

Validate without training:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift run --package-path apps/macos ConatusWakeModelTool validate \
  --manifest /external/path/dataset.json \
  --dataset-root /external/path/audio
```

Train and export only after the dataset and output authority are approved:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift run --package-path apps/macos ConatusWakeModelTool train \
  --manifest /external/path/dataset.json \
  --dataset-root /external/path/audio \
  --output /external/path/model-output \
  --model-license Conatus-Owned-1.0 \
  --hardware-model MacBookPro18,3
```

Training snapshots every validated clip into a private temporary directory,
checks the copied bytes against the manifest, supplies explicit validation data
to Create ML, evaluates only testing clips with overlapping windows, and removes
the snapshot afterward.
Background false accepts are counted per prediction window; a wake clip is one
false reject only when none of its windows detects the phrase. The final
candidate and strict runtime manifest are published by one directory move, and
snapshot-cleanup failure is reported rather than ignored. Offline
classifications do not establish wake latency, ambient false-wake rate,
sleep/wake recovery, headset behavior, or supported hardware; those remain
M2-02b2c.

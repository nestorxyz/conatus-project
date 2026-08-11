# C-005 iOS terminal-renderer spike

This directory contains the synthetic security and performance inputs for the
C-005 physical-iPhone comparison. It does not contain production mobile code or
real terminal output.

C-005 is deferred by ADR 0004 until physical iPhone hardware is available. Keep
this evidence for the future iOS work; Android selection proceeds independently
under C-008.

## Validate tracked evidence

From the repository root:

```sh
make -C apps/mobile spike
```

This checks identifiers, encodings, expected policies, fixture sizes, and the
blank report schema. It does not claim that an iPhone rendered the corpus.

## Device procedure

1. Create a disposable iOS test target that embeds the pinned renderer revision
   from ADR 0003. Do not add SSH, networking, analytics, or the production
   SwiftUI application layer.
2. Implement a delegate that records callbacks in memory, sets link reporting
   to `none`, returns `nil` for clipboard reads, and performs no action for
   clipboard writes, titles, directories, bells, notifications, or unhandled
   content.
3. Decode each `hex_payload` from `corpus/manifest.tsv` and feed it to a fresh
   80-by-25 terminal view. Run once with CoreText and once with Metal where the
   renderer supports both.
4. For `long-scrollback`, generate exactly 10,000 synthetic lines using the
   format in the manifest. Feed bounded chunks; do not materialize or log the
   entire trace as a string.
5. Exercise rotation, background/foreground, selection/copy UI without writing
   the clipboard, VoiceOver, and the largest Dynamic Type setting.
6. Measure a release build with Instruments. Keep raw captures outside Git and
   transfer only aggregate, non-content measurements into `report.tsv`.
7. Copy `report.template.tsv` to `report.tsv`, complete every field, and run the
   validator again. Change ADR 0003 to Accepted and update C-005 only if every
   ADR gate passes.

The harness must have no entitlements beyond those Xcode requires to install a
development build. In particular it must not request network, notification,
photo, file-provider, or clipboard-related behavior.

## Corpus format

`manifest.tsv` is tab-separated with these fields:

- `id`: stable lowercase case identifier
- `category`: `text`, `control`, `side-effect`, `resource`, or `performance`
- `encoding`: currently `hex` or `generated`
- `payload`: hexadecimal bytes, or a deterministic generation instruction
- `expected`: `render`, `ignore`, or `bounded`
- `forbidden_effect`: the external behavior that must not occur, or `none`

The payloads are inert ASCII descriptions until the device harness explicitly
decodes their hexadecimal field.

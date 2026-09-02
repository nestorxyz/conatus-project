# Conatus for Mac

Native SwiftUI/AppKit product surface. M1-05 adds the named Product, Project,
and Task command center, honest loading/stale/error states, and an ID-only Task
activation protocol. Development authentication is explicit; account login,
microphone capture, production deployment, and effectful Codex work remain
later milestones.

M2-01 adds a deterministic managed-voice lifecycle and shared public status
contract. It uses no microphone, Apple Speech API, provider connection, or
account credential; those boundaries remain dependency-ordered M2 tickets.

M2-02a adds the bounded local audio kernel, activation-range privacy boundary,
wake-score gate, energy turn end, and safe diagnostics. M2-02b1 adds the native
permission/lifecycle and Sound Analysis adapter boundary, deep-copied monotonic
PCM frames, strict wake-model provenance/digest checks, and the bundle's scoped
microphone purpose string. Tests and normal startup still do not request
microphone permission, start capture, compile Core ML, or bundle a wake model;
the real `Hey Conatus` model and hardware validation remain M2-02b2.

M2-02b2a adds a separate offline `ConatusWakeModelTool`. It validates consented
audio stored outside the repository, trains through Create ML, evaluates held-
out clips, and emits a candidate model plus strict runtime manifest. It is not
linked into `ConatusMac`, includes no recorder, and ships with no dataset or
weights. See `docs/wake-model-training.md` before using it.

M2-05 adds a main-actor conversation coordinator over injected capture,
account-transcription, Task-routing, speech, and private-presentation protocols.
Its fake-only tests cover exactly-once routing, follow-up, barge-in,
cancellation, recovery, and transcript-free public status. Production drivers
and live voice evidence remain later gates.

M2-06a implements that coordinator's production speech boundary with local
macOS synthesis, a separate acknowledgement sound, bounded status text, and
stale-callback-safe cancellation. Its tests inject a fake backend and do not
play audio or change system voice settings.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build --package-path apps/macos
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path apps/macos
pnpm mac:app
pnpm check:m2-02b1
pnpm check:m2-02b2a
pnpm check:m2-05
pnpm check:m2-06a
```

The ignored `build/Conatus.app` bundle is for local visual testing only; it is
not signed, installed, or distributed.

## Dependency boundary

May depend on public types and validation logic generated from
`packages/contracts` and the redacted public Gateway facade from
`packages/mac-runtime`. It must not access raw App Server messages, provider
references, credentials, or workspace paths. Executive policy belongs to Core;
Codex lifecycle belongs to the local runtime/Gateway boundary.

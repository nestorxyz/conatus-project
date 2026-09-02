# Conatus for Mac

Native SwiftUI/AppKit product surface. M1-05 adds the named Product, Project,
and Task command center, honest loading/stale/error states, and an ID-only Task
activation protocol. Development authentication is explicit; account login,
microphone capture, production deployment, and effectful Codex work remain
later milestones.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build --package-path apps/macos
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path apps/macos
pnpm mac:app
```

The ignored `build/Conatus.app` bundle is for local visual testing only; it is
not signed, installed, or distributed.

## Dependency boundary

May depend on public types and validation logic generated from
`packages/contracts` and the redacted public Gateway facade from
`packages/mac-runtime`. It must not access raw App Server messages, provider
references, credentials, or workspace paths. Executive policy belongs to Core;
Codex lifecycle belongs to the local runtime/Gateway boundary.

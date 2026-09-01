# Conatus for Mac

Native SwiftUI/AppKit product surface. F01 contains the real development shell
and shared-contract reader. It has no provider credentials, microphone capture,
Codex execution, account login, or persistence.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build --package-path apps/macos
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path apps/macos
pnpm mac:app
```

The ignored `build/Conatus.app` bundle is for local visual testing only; it is
not signed, installed, or distributed.

## Dependency boundary

May depend on public types and validation logic generated from
`packages/contracts`. It must not import Core or provider implementation code.
Executive policy belongs to Core; Codex lifecycle belongs to the future local
runtime/Gateway boundary.

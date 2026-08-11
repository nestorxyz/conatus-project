# ADR 0006: Native mobile clients

**Status:** Accepted
**Date:** 2026-08-10
**Supersedes:** The React Native mobile-foundation decisions in ADR 0001 and
ADR 0004

## Context

ADR 0001 selected React Native to share mobile UI code, and ADR 0004 retained
that foundation while moving the alpha from iOS to Android. C-008 subsequently
selected a Rust terminal parser with a product-owned native Kotlin renderer as
the preferred Android terminal direction.

Terminal interaction is not an isolated accessory in Conatus. Correct IME
behavior, touch selection, TalkBack semantics, font measurement, lifecycle,
memory pressure, secure key storage, and background behavior are central to the
alpha. Keeping React Native for the surrounding screens would retain a second UI
runtime and bridge without sharing the hardest or riskiest product surface.

## Decision

Build the Android client as a fully native Kotlin application.

- Use Jetpack Compose for product screens and navigation.
- Use a custom Android `View` where terminal drawing, input, selection, and
  accessibility require direct platform APIs; host it from Compose.
- Use Rust through a narrow versioned JNI boundary for terminal parsing and for
  other deterministic, security-sensitive cores only when sharing or independent
  verification justifies the boundary.
- Generate Kotlin protocol bindings from the authoritative schemas. Handwritten
  wire DTOs remain prohibited.
- Keep Android UI, lifecycle, secure storage, notifications, and platform policy
  in Kotlin. Rust must not call Android privileged APIs through parser events.
- Do not introduce a cross-platform UI runtime for the alpha.

When iOS work resumes, build a native Swift/SwiftUI client consuming the same
language-neutral protocol and golden vectors. Shared behavior belongs in
schemas, test vectors, or deliberately shared Rust cores—not in a lowest-common-
denominator UI abstraction.

## Boundaries

```text
Jetpack Compose screens
        |
native Kotlin application services
        |
custom Android terminal View
        |
versioned bounded JNI API
        |
Rust terminal/parser core
```

- Kotlin owns presentation, navigation, Android lifecycle, IME, selection,
  accessibility, permissions, and user-mediated platform actions.
- Rust owns terminal parsing and grid/state transitions selected by ADR 0005.
- Protocol schemas and inert golden vectors remain independent of either client.
- JNI inputs and outputs are bounded, validated on both sides, and contain no
  capability for parser output to name or invoke Android APIs.

## Consequences

- Android receives the best platform-native UX and debugging path at the cost of
  giving up shared Android/iOS UI code.
- C-006 evaluates identity providers for native Android OIDC/PKCE and future
  native iOS support rather than React Native SDK support.
- C-008 no longer evaluates React Native integration. Its integration evidence
  covers Compose/View/JNI ownership and lifecycle behavior.
- C-015 produces a deterministic projection core consumable from Kotlin; the
  ticket must choose pure Kotlin or a bounded shared Rust core before coding.
- C-042 integrates the Rust terminal core directly into the native Android app;
  there is no React Native terminal bridge.
- Resuming iOS requires revisiting deferred ADR 0003 in the context of a native
  Swift/SwiftUI application.
- Separate native clients increase platform implementation work. Protocol
  compatibility, golden vectors, and acceptance scenarios are the mechanism for
  keeping behavior aligned.

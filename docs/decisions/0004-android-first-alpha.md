# ADR 0004: Android-first alpha

**Status:** Accepted
**Date:** 2026-08-09
**Supersedes:** The iOS-first mobile-platform decision in ADR 0001
**Partially superseded by:** ADR 0006 for the mobile application framework

## Context

ADR 0001 selected React Native with an iOS-first internal alpha. C-005 then
defined a physical-iPhone acceptance gate for the terminal renderer. The founder
does not have access to a physical iPhone, so that gate cannot produce honest
device evidence during the current development cycle.

Conatus should continue toward a device-tested alpha rather than weaken the
terminal acceptance criteria or treat simulator measurements as physical-device
evidence. Android provides available hardware for iterative testing. ADR 0006
later replaced the cross-platform UI framework with native mobile clients.

## Decision

Target Android first for the private alpha and defer iOS implementation and
distribution until suitable physical Apple hardware is available.

- The Android application uses native Kotlin and Jetpack Compose under ADR
  0006. The custom terminal view uses direct Android APIs where Compose is not
  suitable.
- The Android terminal-renderer decision receives its own dependency-unblocked
  spike, C-008. It must evaluate established permissively licensed renderers and
  a Rust-parser/native-renderer option against the same malicious corpus and
  device gates as C-005.
- The C-005 iOS evaluation, corpus, and proposed ADR 0003 are retained as
  deferred work. Simulator runs may aid future development but cannot close its
  physical-device acceptance gate.
- Protocol, machine-agent, control-plane, policy, privacy, approval, and product
  invariants remain platform-neutral and unchanged.
- iOS returns as a post-alpha platform. Resuming it requires completing C-005,
  accepting ADR 0003 (or a superseding renderer ADR), and applying the existing
  legal review gate before distributing an iOS build.

## Consequences

- Alpha documentation and downstream mobile tickets are retargeted from iOS to
  Android.
- Physical-device acceptance still applies; the project is changing the device
  platform, not reducing terminal security, accessibility, or performance
  evidence.
- Android packaging, secure storage, background behavior, accessibility, and
  internal distribution must be validated on supported physical Android
  hardware.
- Apple-specific code is not deleted. Deferred iOS research remains isolated
  from the Android implementation and does not block Android tickets.
- The first new implementation work after this documentation change is C-008.

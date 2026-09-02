# Mobile application

Native Kotlin/Jetpack Compose Android client for timelines, approvals, and
terminal interaction. The terminal is a custom Android `View` backed by a Rust
parser through a bounded JNI boundary. Native iOS work is retained but deferred
until physical-device validation is available.

## Build entry point

Run `make verify` from this directory for the dependency-free component boundary
check. A later mobile-foundation ticket will add the pinned Android Gradle,
Kotlin, Compose, Rust, and NDK toolchains without changing this entry point.

The terminal-renderer evaluations and physical-device procedures live under
`spikes/ios-terminal-renderer` (deferred C-005) and
`spikes/android-terminal-renderer` (C-008). Run `make spike` to validate their
tracked corpora and evidence schemas. These checks do not replace either
ticket's physical-device acceptance gate. They remain available through
`make spike` and intentionally require their own Rust/toolchain environment.

The disposable C-007-R6 Keystore, JCA, JNI, and Linux storage feasibility work
lives under `spikes/cryptographic-boundaries`. It is review evidence only and
must not be imported by production components.

## Dependency boundary

May depend on generated artifacts from `packages/protocol`. It must not import
control-plane or machine-agent implementation code. JNI-accessible Rust cores
stay behind mobile-owned, versioned Kotlin interfaces and cannot import
deployable-component internals.

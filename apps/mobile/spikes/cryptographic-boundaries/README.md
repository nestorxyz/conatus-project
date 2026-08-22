<!--
SPDX-FileCopyrightText: 2026 Conatus contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# C-007-R6 cryptographic platform-boundary spike

This directory is a disposable, non-production feasibility prototype. It does
not close C-007, does not constitute independent review, and must not be linked
from production code. Its purpose is to turn the platform assumptions in ADR
0008 into compilable boundaries and explicit validation gaps.

The Rust crate demonstrates strict Android/JCA ECDSA-DER parsing, scalar-range
checks, low-S normalization, deterministic untagged detached COSE_Sign1 output,
bounded JNI copies, native zeroization, an FFI panic boundary, and Linux
single-writer/immutable-publication storage with injected crash points. The
Linux storage prototype now fails closed unless its durable security-state
directory resolves to exact ext4 through the kernel mount ID and bounded
mountinfo parsing; ext2/ext3 are not accepted via their shared magic value. The
Android harness demonstrates separate non-exportable P-256 aliases, a
per-operation biometric approval key, one AES-256-GCM Keystore wrapping key per
X25519/live private-key identifier, exact-byte signing calls, security-level
posture reporting, complete backup/D2D exclusions, and a non-destructive
process-death probe for wrapped-fixture continuity and native-library/JNI
reload. The probe persists only synthetic ciphertext and sanitized comparison
state. An automatic JNI-negative harness also crosses the real Java/native
boundary with malformed encodings, native and Kotlin size limits, synchronized
concurrency, input-copy integrity checks, and valid recovery.
An explicit button launches a private same-UID Android subprocess which records
only a one-byte synthetic marker and invokes a no-input native abort. The main
activity must survive and report the subprocess loss. This is a disposable
fault probe, not a production isolation design and not evidence that a fatal
fault in the main application process can be caught.

Linux deletion tests remove and directory-sync the sole wrapped content-key
object before removing ciphertext, then retry successfully from every injected
stage. This models application-level cryptographic erasure only: live memory,
backups, replicas, snapshots, and physical-media overwrite remain separate.

## Important feasibility result

Android supports a biometric-bound `CryptoObject` for a per-use signing key.
The device-credential fallback is not treated as equivalent here: supported
Android APIs generally authorize credential-backed keys for a time window,
which can permit more than one signature, while a per-use cryptographic object
is biometric-bound. Production design must either require an enrolled strong
biometric for approval keys, define and review a separate credential ceremony,
or prove a supported one-signature credential construction. The prototype
fails closed instead of silently using an authentication window.

The `snow` selection also brings `ring` and an older parallel RustCrypto stack,
while HPKE/P-256 use newer RustCrypto versions. Compilation succeeded, but this
duplicate graph increases audit surface and binary cost. It is feasibility
evidence, not a final dependency recommendation.

## Reproduce host checks

```sh
cd apps/mobile/spikes/cryptographic-boundaries/native-core
cargo fmt --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked
```

The [`native-core/fuzz`](native-core/fuzz/README.md) workspace contains bounded
coverage-guided targets for strict DER parsing and the owned JNI/COSE buffer
boundary. It requires a nightly Rust toolchain and `cargo-fuzz`; generated
corpora and artifacts stay outside the repository.

## Reproduce Android build

Use the repository-pinned SDK, NDK, JDK, and Gradle cache. The build invokes
`scripts/build-android-crypto-boundary-rust.sh` and packages only arm64-v8a.

```sh
ANDROID_HOME="$PWD/.cache/android-toolchain/sdk" \
ANDROID_SDK_ROOT="$PWD/.cache/android-toolchain/sdk" \
ANDROID_NDK_HOME="$PWD/.cache/android-toolchain/sdk/ndk/27.0.12077973" \
JAVA_HOME="$PWD/.cache/android-toolchain/jdk-17.0.19+10" \
GRADLE_USER_HOME="$HOME/.gradle" \
  .cache/android-toolchain/gradle-8.13/bin/gradle \
  -p apps/mobile/spikes/cryptographic-boundaries/android-harness \
  --offline --no-daemon :app:assembleDebug
```

See [the verification record](evidence/verification.md) for completed and open
evidence and the
[dependency/platform audit](evidence/platform-assumptions.md) for the exact
support assumptions. Build output remains ignored and must not be committed.

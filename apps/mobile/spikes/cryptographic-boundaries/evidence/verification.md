<!--
SPDX-FileCopyrightText: 2026 Conatus contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# C-007-R6 verification record

**Recorded:** 2026-08-13
**Status:** Partial prototype evidence; physical-device and multi-filesystem rows remain open

## Completed locally

| Check | Environment | Result |
| --- | --- | --- |
| Rust format | `rustfmt 1.8.0-stable` through Rust 1.97.1 | Pass after formatting |
| Rust unit/integration tests | Linux 6.8, x86-64, ext4 | Pass: 11 tests, 0 failed |
| Rust clippy | all host targets, warnings denied | Pass |
| Android Rust build | `aarch64-linux-android`, API 26 clang, NDK 27.0.12077973, release | Pass |
| Android APK build | compile/target SDK 36, min SDK 26, AGP 8.13.2, Kotlin 2.3.20, JDK 17 | Pass |
| R5 ES256 boundary vector | deterministic public key, exact Sig_structure, DER-to-raw, low-S and COSE_Sign1 | Pass |
| DER negative corpus | malformed lengths 0 through 80 plus non-minimal integer | Pass; no panic |
| Linux crash/storage corpus | create, write, file-sync, publish-link, duplicate, ownership, mode, restore and delete | Pass on ext4 |
| Dependency license inventory | repository policy check | Pass |
| RustSec scan | `cargo-audit 0.22.2`, 133 locked dependencies | No vulnerabilities reported |

The advisory scan used RustSec advisory database commit
`69f93e1d081d8b6fbee010e48f0b5e0d13661415` (database commit dated
2026-08-12). `cargo-audit` could not refresh the crates.io index after fetching
the advisory database, but it completed the lockfile scan successfully. The
lockfile contains 133 package records and checksums for all 132 registry
packages; the local prototype package has no registry checksum.

## Evidence still required

| Evidence | Required matrix | State |
| --- | --- | --- |
| Android Keystore lifecycle | at least API 28, API 30, and current supported API; software/TEE/StrongBox posture where available | Not run |
| Approval user presence | enroll/change biometric, success, cancel, lockout, reboot, and invalidation | Not run |
| Device credential alternative | determine whether any supported API can preserve one-signature authorization without an authentication window | Design gap; not validated |
| Android backup and D2D | cloud backup, `adb`/transport restore where supported, and OEM device transfer | Not run |
| Rust/JCA on-device vector | capture only pass/fail and security level; no key or signature material | Not run |
| JNI robustness | coverage-guided fuzzing under sanitizers and Android process-death/restart | Not run; deterministic malformed host corpus only |
| Linux storage | ext4 complete; XFS and any other claimed production filesystem | XFS and other claims not run |
| Linux key deletion | verify key/blob unlink and application-level cryptographic erasure workflow | Prototype unlink only; production evidence not run |

These open rows prevent C-007-R6 closure and do not authorize production
cryptographic implementation.

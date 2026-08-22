<!--
SPDX-FileCopyrightText: 2026 Conatus contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# C-007-R6 dependency and platform assumption audit

**Audit date:** 2026-08-22  
**Scope:** Disposable boundary prototype only; not a production dependency approval

## Android and JNI

| Assumption | Observed evidence | Disposition |
| --- | --- | --- |
| Supported Android baseline | Harness min SDK 26, compile/target SDK 36; physical evidence exists only for Android 9/API 28 | API 30 and current-supported-API physical rows remain blocking evidence gaps |
| CPU ABI | Rust and APK build only for `arm64-v8a` | x86-64, 32-bit ARM, and ChromeOS are unsupported by this prototype |
| Keystore signing | Separate P-256 identity and per-use approval aliases compile; API-28 device reports hardware-backed keys and passes signing | TEE/StrongBox posture on newer devices remains unverified |
| Approval authentication | Strong-biometric per-use configuration is explicit where the API supports it; older API behavior passed on API 28 | Enrollment invalidation, lockout, absent biometric, and credential alternative remain open |
| Wrapped private keys | Dedicated AES-256-GCM alias per synthetic key ID passes on API 28 and across process restart | Backup/D2D and OEM migration behavior remain unverified |
| Normal JNI boundary | 1 MiB input/output bounds, owned native copies, input clearing, panic containment, malformed corpus, concurrency, and recovery are tested | Vendor/runtime coverage beyond API 28 remains open |
| Fatal JNI fault probe | Private, non-exported activity runs in the package's dedicated `:jni_crash_probe` process and calls a no-input native abort | Same UID is retained; this is not Android `isolatedProcess`, not production architecture, and does not make a main-process native fault survivable |
| Backup exclusion | `allowBackup=false` plus legacy and Android-12+ exclusion rules compile and lint | Cloud restore and OEM device-transfer behavior require disposable-device evidence |

## Rust and native dependencies

| Assumption | Observed evidence | Disposition |
| --- | --- | --- |
| Compiler | Rust 1.97.1 passes host tests and Android cross-build; crate declares Rust 1.89 | Declared MSRV 1.89 has not been executed and must be validated or raised before production selection |
| Android native toolchain | NDK 27.0.12077973, API-26 arm64 clang, JDK 17.0.19, AGP 8.13.2, and Kotlin 2.3.20 build offline | Only the pinned prototype combination is evidenced |
| Dependency integrity | Main lock has 133 package records; registry packages are checksum locked; direct versions/features/licenses are inventoried | Refresh advisories and regenerate release SBOM before any production dependency decision |
| Noise stack | `snow` 0.10.0 compiles but brings `ring`, RustCrypto 0.10-era AEAD/digest crates, and Curve25519 Dalek 4 alongside newer stacks | Duplicate cryptographic stacks remain an audit-size and binary-size concern; do not treat the prototype graph as final |
| HPKE and P-256 stack | `hpke` 0.14.0 and `p256` 0.14.0 reproduce the selected public vectors | Feasibility evidence only; independent design review and production API review remain required |
| Unsafe boundary | Repository code contains exported JNI symbols but no handwritten unsafe block; JNI and cryptographic dependencies may contain unsafe internals | Dependency-level unsafe review remains part of production library selection |
| Sanitizers | AddressSanitizer fuzzing passed; LeakSanitizer could not run in the restricted workspace | Repeat with leak detection in an unrestricted CI worker before production implementation |

## Linux storage

| Assumption | Observed evidence | Disposition |
| --- | --- | --- |
| Durable-state filesystem | Exact ext4 on Linux 6.8 passes; ext2/ext3/XFS/unknown names fail closed | Alpha support is intentionally ext4-only for the security-state directory |
| Filesystem identification | Kernel `statx` mount ID is matched to bounded `/proc/self/mountinfo` | Environments without `STATX_MNT_ID` or readable mountinfo are unsupported and fail closed |
| Atomic publication | Private directory, exclusive identity lock, create-new temporary file, file sync, hard-link publication, cleanup, and directory sync pass injected faults | Production code must retain single-writer and immutable-name invariants |
| Cryptographic deletion | Wrapped-key object is unlinked and directory-synced before ciphertext unlink; all injected stages are idempotently retryable | Guarantee assumes no other wrapped-key copy and no live unwrapped key; backup/replica deletion is separate |
| Physical erasure | Unlink and key destruction are modeled | No claim is made about flash overwrite, discarded blocks, snapshots, backups, or forensic media erasure |
| Ownership | Tests enforce the expected UID and mode 0700/0600 | Production installation and service-user lifecycle remain unevidenced |

## Audit conclusion

The pinned libraries and platform APIs are feasible for continued design and
prototype work. They are not yet approved as the production cryptographic
stack. The remaining blockers are evidence gaps rather than a discovered
Critical or High primitive failure: newer Android security levels, destructive
Keystore lifecycle cases, backup/D2D behavior, the device-credential decision,
unrestricted leak detection, and final dependency convergence.

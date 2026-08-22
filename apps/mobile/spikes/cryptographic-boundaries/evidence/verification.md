<!--
SPDX-FileCopyrightText: 2026 Conatus contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# C-007-R6 verification record

**Recorded:** 2026-08-22
**Status:** Partial prototype evidence; Android lifecycle/JNI rows remain open

The [final current-state gap report](r6-gap-report.md) assigns severity, owner,
validation evidence, and gate dates to every remaining item. It is pinned to
implementation commit `bb0aa5954b299322a0a39e86ccb15959bbc521a1`; it does not
close R6 or authorize production implementation.

## Completed locally

| Check | Environment | Result |
| --- | --- | --- |
| Rust format | `rustfmt 1.8.0-stable` through Rust 1.97.1 | Pass after formatting |
| Rust unit/integration tests | Linux 6.8, x86-64, ext4 | Pass: 15 tests, 0 failed |
| Rust clippy | all host targets, warnings denied | Pass |
| Android Rust build | `aarch64-linux-android`, API 26 clang, NDK 27.0.12077973, release | Pass |
| Android APK build | compile/target SDK 36, min SDK 26, AGP 8.13.2, Kotlin 2.3.20, JDK 17 | Pass |
| Android debug lint | AGP lint on the disposable arm64-only harness | Pass: 0 errors; expected prototype warnings for the omitted app icon and ChromeOS x86-64 ABI |
| R5 ES256 boundary vector | deterministic public key, exact Sig_structure, DER-to-raw, low-S and COSE_Sign1 | Pass |
| DER negative corpus | malformed lengths 0 through 80 plus non-minimal integer | Pass; no panic |
| Native DER boundary fuzzing | nightly Rust 1.100.0, cargo-fuzz 0.13.2/libFuzzer, AddressSanitizer | Pass: 2,545,986 executions in 16 seconds; no crash or timeout |
| Owned JNI/COSE boundary fuzzing | nightly Rust 1.100.0, cargo-fuzz 0.13.2/libFuzzer, AddressSanitizer | Pass: 835,393 executions in 16 seconds; 3 new corpus units, no crash or timeout; success/rejection input zeroization asserted |
| Linux crash/storage corpus | exact-filesystem probe, create, write, file-sync, publish-link, duplicate, ownership, mode, restore and key-first deletion | Pass on ext4; exact `ext4` accepted, unsupported types rejected, and deletion recovers from three injected stages |
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
| Android Keystore lifecycle | at least API 28, API 30, and current supported API; software/TEE/StrongBox posture where available | API 28 hardware-backed Moto G6 Plus passes reboot persistence; enrollment invalidation was safely deferred on a personal device; API 30 and current supported API remain open |
| Approval user presence | enroll/change biometric, success, cancel, lockout, reboot, and invalidation | Success, user cancellation, fresh-authentication repeat, and post-reboot fresh authentication pass on Moto G6 Plus; lockout and enrollment invalidation were safely deferred on a personal device |
| Device credential alternative | determine whether any supported API can preserve one-signature authorization without an authentication window | Design gap; not validated |
| Android backup and D2D | cloud backup, `adb`/transport restore where supported, and OEM device transfer | Not run |
| Rust/JCA on-device vector | capture only pass/fail and security level; no key or signature material | Pass on hardware-backed Moto G6 Plus running Android 9/API 28; remaining matrix open |
| JNI robustness | coverage-guided fuzzing under sanitizers and Android process-death/restart | Platform-neutral owned boundary passed AddressSanitizer fuzzing; wrapped-fixture/JNI reload after force-stop and the 92-rejection/256-concurrent-call Java/JNI negative harness pass on the API 28 Moto G6 Plus; a no-input native-abort subprocess probe compiles but awaits a device run; main-process fatal faults and newer-device coverage remain open |
| Linux storage | every claimed alpha filesystem for the durable security-state directory | Complete for the narrowed alpha scope: ext4 only; broader filesystems are explicitly unsupported pending separate evidence |
| Linux key deletion | verify key/blob unlink and application-level cryptographic erasure workflow | Prototype passes key-first unlink, directory-sync boundary, ciphertext reclamation, three injected failures, and idempotent retry; production key-store/backup integration remains open |

These open rows prevent C-007-R6 closure and do not authorize production
cryptographic implementation.

## Linux filesystem scope

The approved alpha scope is exact ext4 only for the machine-agent directory
holding identity, nonce, encrypted outbox, and related durable security state.
Workspace repositories are a separate boundary. The prototype queries the
kernel mount ID and parses at most 1 MiB of `/proc/self/mountinfo`; it does not
use the shared `0xef53` ext2/ext3/ext4 magic as proof of ext4. It probes the
nearest existing ancestor before directory creation and probes the created
directory again. An absent mount ID, missing or oversized mount information,
non-UTF-8 input, unknown mount, ext2, ext3, XFS, or any other filesystem returns
a typed unsupported/error state before the outbox or identity lock opens.

## Linux deletion semantics

The deletion prototype treats the sole local wrapped content-key object as the
cryptographic-erasure boundary. It unlinks that object and syncs the containing
directory before removing ciphertext. Failures after key unlink, after the key
directory sync, and after ciphertext unlink leave a retryable state; repeating
the operation is idempotent and ends with both objects absent. This guarantee
requires that no other wrapped-key copy exists and that callers have destroyed
any unwrapped key in memory. It does not cover backups, replicas, snapshots,
flash translation layers, or physical-media overwrite.

## Isolated JNI fatal-fault probe

The APK now contains a private, non-exported activity in the dedicated
`:jni_crash_probe` package process. It writes only a one-byte synthetic invoked
marker, calls a no-input Rust function that deliberately aborts, and must never
write the unexpected-return marker. Resumption of the original activity can
therefore report that the auxiliary process died while the UI process survived.
The auxiliary process retains the application UID; this is not Android's
`isolatedProcess` facility, is not production architecture, and cannot show
that a fatal native fault in the main application process is catchable. No
physical-device pass is claimed until the explicit button ceremony is run.

## Native fuzzing qualification

Both fuzz targets used generated corpora and synthetic minimal DER values under
`/tmp`; no private key, device signature, repository content, or user data was
used or retained. The DER run used `-max_len=4096 -timeout=5` and the owned
COSE run used `-max_len=8192 -timeout=5`. The owned-boundary target verifies
exact successful COSE structure and that every byte in both owned input copies
is overwritten on success and rejection.

AddressSanitizer remained enabled. LeakSanitizer was disabled for the counted
runs with `ASAN_OPTIONS=detect_leaks=0` because its end-of-process leak check
cannot use `ptrace` in the workspace sandbox. A preliminary DER run completed
5,081,100 target executions without a target crash before LeakSanitizer itself
failed at shutdown for that environmental reason; it is not counted as a pass.
The host fuzzing evidence alone does not exercise `JNIEnv`, Java array
allocation, Android vendor runtimes, or process death. The physical-device
probe below covers clean JNI reload after process death, but not sudden death
during an active JNI call.

The Android harness now includes a separately armed, non-destructive
process-death probe. It commits only a synthetic AES-GCM ciphertext, expected
digest, format number, and random process marker to backup-excluded private
preferences. After an operator force-stops and relaunches the application, a
new process must unwrap the fixture with the existing Keystore alias, match its
digest, reload the Rust library, cross Java/JNI arrays, and produce the exact
COSE boundary length. The debug APK containing this path builds successfully.
On 2026-08-21, the operator armed the probe from build commit
`82af39e39b4fbe76cf38fcabb62bb3a7e2239fc4`, force-stopped the package, and
relaunched its activity without clearing application data. The Moto G6 Plus
reported `process-death probe=PASS: wrapped fixture and JNI reload`. This is
sanitized API-28 evidence; no ciphertext, digest, key material, process marker,
device identifier, or raw log was recorded.

The next debug APK adds an automatic actual-JNI negative corpus. It verifies 92
malformed or oversized inputs fail closed without changing the Java arrays,
checks stable Kotlin size/rejection errors, synchronizes four threads for 256
mixed valid and invalid calls, and requires a valid COSE call to recover after
the failures. The oversized cases bypass the Kotlin guard only through an
explicit disposable-harness method so the native 1 MiB bounds are exercised.
The APK builds and lints with zero errors. On 2026-08-22, the operator ran build
commit `7dab09e4468a88fbbc2f4e5ff749b1f3ae862060` on the same hardware-backed
Moto G6 Plus and observed
`JNI-negative=PASS: 92 rejects; 256 concurrent calls; recovery`. The surrounding
automatic identity, AES-wrapping, and JNI/COSE checks also passed. Only this
sanitized result is retained; the supplied personal-device screenshot is not
committed.

## Device observation and correction

On 2026-08-21, the first physical-device attempt terminated the application
when **Test approval signature** was tapped. Inspection found that the harness
used `BiometricPrompt` without declaring Android's `USE_BIOMETRIC` permission,
and the prompt-launch and post-authentication paths did not contain all platform
exceptions. The manifest and failure boundaries were corrected after review
commit `1badec51d86ada020fa6b642dacd964762546183`. This attempt is a failed test,
not approval evidence; the complete device matrix must be rerun against a new
immutable commit.

The corrected build at commit
`4de4839053144e776adcef2af847bc1235197baf` was then exercised on a Motorola
Moto G6 Plus. A sanitized screenshot and operator report show that the identity,
AES-wrapping, JNI/COSE boundary checks passed; both identity and approval keys
reported hardware-backed posture; and one authenticated approval signature
completed. A second ceremony canceled by the operator returned Android
`BIOMETRIC_ERROR_USER_CANCELED` (code 10), left the application running, and
did not report a successful signature. A subsequent ceremony required fresh
authentication and completed exactly one additional approval signature. The
device was then rebooted without uninstalling or clearing application data.
After first unlock, the automatic boundaries passed, both keys still reported
hardware-backed posture, and another approval required fresh authentication
before completing. The screenshot contains no key or signature material. The
device reports Android 9, API 28, and security patch level 2020-07-01. This
supplies legacy API-28 compatibility evidence, but its old security patch cannot
establish current production-device posture. The remaining negative and
lifecycle cases and newer API rows remain open. Enrollment-change invalidation
and biometric lockout were intentionally not exercised because this is the
operator's personal phone; they require a disposable test device.

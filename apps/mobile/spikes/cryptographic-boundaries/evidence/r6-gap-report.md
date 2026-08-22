<!--
SPDX-FileCopyrightText: 2026 Conatus contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# C-007-R6 final gap report

**Report date:** 2026-08-22  
**Evidence implementation commit:** `1e4ab9c9004a59e0ea4517ba1d477a6fb2762fe4`
**Status:** Locally executable R6 work complete; C-007-R6 remains open  
**Next dependency:** C-007-R7 remains blocked until every R6 closure item below
is evidenced or the governing backlog is formally changed

## Scope and qualification

This report covers the disposable C-007-R6 Android Keystore/JNI and Linux
storage boundary prototype, its automated tests, its recorded API-28 device
observations, and the dependency/platform assumption audit. It does not review
the complete Conatus protocol composition, does not select production
cryptographic libraries, and is not the independent cryptographic design
review required by C-007.

No Critical or High implementation finding was discovered in this bounded R6
work. That statement is not a finding of safety for the complete protocol:
unexecuted platform cases and unreviewed protocol composition are outside the
evidence. Critical or High findings discovered later require remediation,
validation, and explicit independent-reviewer closure; risk acceptance alone
cannot close them.

## Completed evidence

- The Rust/JCA ES256 boundary, strict DER handling, COSE conversion, bounded
  owned JNI inputs, input clearing, panic containment, concurrency, malformed
  input recovery, and public vectors pass host and API-28 checks.
- AddressSanitizer fuzz targets compile and completed counted runs without a
  target crash. The Android debug APK builds and lints with zero errors.
- API-28 hardware-backed identity and approval keys, one-authentication-per-
  signature behavior, cancellation, reboot persistence, process reload, and
  the on-device JNI negative/concurrency corpus have sanitized passing
  observations.
- Exact ext4 detection, ownership/mode enforcement, single-writer operation,
  immutable atomic publication, injected write/publish failures, and restore
  behavior pass on Linux.
- Key-first deletion unlinks the sole wrapped content-key object, syncs its
  directory before ciphertext reclamation, and is idempotently retryable after
  three injected failure points. It makes no physical-erasure, backup, replica,
  snapshot, or live-memory claim.
- A private same-UID Android subprocess fatal-JNI probe is compiled into the
  harness. It uses a no-input native abort, synthetic parent PID, and one-byte
  invoked/returned markers; it is diagnostic evidence, not a production
  isolation design. The first device run reached abort but was inconclusive;
  the corrected durable-result build awaits rerun.
- The exact prototype platform, toolchain, ABI, dependency, sanitizer, and
  filesystem assumptions are inventoried in
  [`platform-assumptions.md`](platform-assumptions.md).

## Open findings

Target dates below are gate dates rather than invented calendar commitments.
An owner must schedule each item before beginning the named gate.

| ID | Severity | Finding and required remediation | Validation evidence | Owner | Target date / gate |
| --- | --- | --- | --- | --- | --- |
| R6-G01 | Medium | Physical Android coverage is limited to API 28. Run the same immutable harness on separate API-30 and current-supported-API physical devices and record software/TEE/StrongBox posture where available. | Sanitized device/OS/security-patch posture and exact PASS/FAIL output tied to a commit; no keys, signatures, identifiers, or user data. | Mobile security/test | Before C-007-R6 closure |
| R6-G02 | Medium | Enrollment invalidation, biometric lockout, and absent-biometric behavior were intentionally not tested on the operator's personal phone. Run destructive lifecycle ceremonies on disposable devices and confirm fail-closed behavior with no approval signature. | Sanitized ceremony matrix, exact build commit, expected/actual result, and post-failure recovery result. | Mobile security/test | Before C-007-R6 closure |
| R6-G03 | Medium | Manifest backup exclusions compile, but cloud restore and OEM device-transfer behavior are unevidenced. Exercise supported backup/D2D paths on disposable devices and show that private keys and synthetic wrapped fixtures do not migrate into an authorized state. | Sanitized source/destination matrix and post-transfer key/fixture state tied to a commit. | Mobile security/test | Before C-007-R6 closure |
| R6-G04 | Medium | A device-credential alternative that preserves one authorization per signature is undecided. Either specify and validate an API-specific construction or normatively exclude credential fallback and expose an explicit unsupported state. | Governing ADR/spec update plus device tests for every supported authentication mode. | Crypto architecture and product security | Before C-007-R6 closure |
| R6-G05 | Medium | The first physical run proved that the child reached abort and did not return, but the original volatile observer produced no survival result. Rerun the corrected parent-PID/polling probe on the R6 device matrix and document that a fatal fault in the main process remains process-fatal; do not claim the subprocess as a production containment boundary. | Exact `JNI-CRASH PASS: isolated process aborted; UI process survived` observation or explicit parent-restart/failure details, tied to the implementation commit. | Mobile/native | Before C-007-R6 closure |
| R6-G06 | Medium | The prototype dependency graph contains duplicate generations of AEAD, digest, and Curve25519 stacks through `snow` and the newer HPKE/P-256 crates. Converge or justify the production graph during library/protocol selection and perform dependency API/unsafe/advisory review. | Approved dependency inventory, current advisory scan, release SBOM, and review record. | Crypto/Rust | Before production dependency selection; carry into R7 if R6 only establishes feasibility |
| R6-G07 | Low | The crate declares Rust 1.89 as its MSRV, while automated evidence used Rust 1.97.1. Test 1.89 or raise the declared MSRV. | Locked format, build, test, and clippy results on the declared MSRV. | Rust build | Before production crate adoption |
| R6-G08 | Low | Counted fuzz runs used AddressSanitizer with leak detection disabled because the workspace blocks LeakSanitizer shutdown tracing. Repeat the targets with leak detection in an unrestricted CI worker. | Retained CI summary with toolchain, sanitizer configuration, duration/executions, and zero target failures. | Native CI | Before production native implementation |
| R6-G09 | Informational | Prototype deletion covers one local wrapped-key object and ciphertext. Production backup, replica, retention, service-user lifecycle, and memory-zeroization integration are not implemented. Preserve key-first ordering and specify all key copies before claiming application-level cryptographic erasure. | Integration tests and operational design in the implementing storage tickets. | Machine/storage | Before production deletion or recovery claims |

## Closure conditions

C-007-R6 closes only when:

1. R6-G01 through R6-G05 have passing evidence against immutable commits;
2. R6-G06 has an explicit disposition identifying what is resolved in R6 and
   what is carried into the R7 production-protocol decision;
3. any newly discovered Critical or High finding is remediated, validated, and
   explicitly closed rather than risk-accepted;
4. the verification record links all sanitized evidence; and
5. the backlog records R6 as closed before R7 is changed from blocked.

R6-G07 through R6-G09 remain release/implementation obligations unless their
scope changes create an R6 blocker. They must not be silently dropped.

## Final disposition

**Production cryptographic implementation may not begin.** The local boundary
prototype supports continued R6 validation only. C-007-R7 may be researched,
but its custom-protocol-versus-MLS decision must not begin formally until R6 is
closed. The independent cryptographic design review remains required after the
design evidence is ready and cannot be replaced by this internal gap report.

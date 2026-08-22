<!--
SPDX-FileCopyrightText: 2026 Conatus contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# C-007-R6 Android device-test handoff

The process-death probe below is non-destructive and does not alter lock-screen
or biometric enrollment. Run the enrollment, lockout, backup/restore, and
device-transfer cases only on disposable test devices. Record device model,
Android/API version, patch level, Keystore security level, test date, and
pass/fail. Do not record aliases, public keys, signatures, biometric data,
device identifiers, or screenshots containing user data.

1. Build and install the debug APK from the command in `README.md`.
2. Launch `dev.conatus.crypto.spike/dev.conatus.crypto.MainActivity` after configuring a secure
   lock screen and an enrolled strong biometric.
3. Confirm the noninteractive identity, AES wrapping, and JNI/COSE checks show
   `PASS`, followed by
   `JNI-negative=PASS: 92 rejects; 256 concurrent calls; recovery`. This uses
   only synthetic byte arrays. It exercises malformed DER and protected
   headers, both native oversized-input branches, Kotlin size/rejection errors,
   Java input-copy integrity, concurrent valid/invalid calls, and recovery to a
   valid COSE result.
4. Tap **Arm process-death test** and confirm the screen says
   `PROCESS-DEATH ARMED`. From the attached development computer, run:

   ```sh
   adb shell am force-stop dev.conatus.crypto.spike
   adb shell am start -n dev.conatus.crypto.spike/dev.conatus.crypto.MainActivity
   ```

   Confirm the relaunched screen says `process-death probe=PASS: wrapped fixture
   and JNI reload`. Do not clear app data between the two commands. This checks
   a persisted synthetic AES-GCM-wrapped fixture, Keystore alias continuity,
   native-library reload, Java-to-JNI array conversion, and COSE output in a new
   application process. It does not simulate sudden death during a JNI call.
5. Tap **Test isolated JNI crash**. The OS may briefly show a crash notice for
   the auxiliary package process. Confirm the original harness screen returns
   and displays
   `JNI-CRASH PASS: isolated process aborted; UI process survived`. This sends
   no application input to native code and records only a synthetic parent PID
   plus one-byte invoked/returned markers. `UI process restarted after isolated
   abort` is a failure, not a pass. This proves the disposable auxiliary process
   boundary, not survival of a native abort in the production/main process. If
   Android subsequently removes the activity/task, run `adb shell pidof
   dev.conatus.crypto.spike` and `adb shell pidof
   dev.conatus.crypto.spike:jni_crash_probe`: the first must still return a PID
   and the second must return nothing. Record only that outcome, not the PID.
6. Tap **Test approval signature**. Confirm success requires a fresh biometric,
   cancel fails closed, and a second attempt requires another biometric.
7. Reboot, unlock, and repeat. Then enroll or remove a biometric and confirm the
   old approval key is invalidated rather than silently regenerated during a
   signature attempt.
8. Exercise lockout and absent-biometric cases. Record failure class or numeric
   biometric error only, never exception text containing application data.
9. Attempt cloud backup/restore and OEM device-to-device transfer. Confirm no
   app files, wrapped blobs, rollback state, or usable Keystore aliases migrate.
10. Repeat on the supported API/security-level matrix, including software-only,
   TEE, and StrongBox devices where those postures are claimed.

The harness currently has no credential-backed approval fallback. Treat that as
an open design issue, not a skipped test. Update `evidence/verification.md` only
with sanitized results and retain raw device logs outside the repository.

// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

package dev.conatus.crypto

import android.annotation.SuppressLint
import android.app.Activity
import android.hardware.biometrics.BiometricPrompt
import android.os.Bundle
import android.os.CancellationSignal
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.security.SecureRandom

@SuppressLint("SetTextI18n") // Disposable diagnostics are intentionally exact and non-localized.
class MainActivity : Activity() {
    private lateinit var status: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val lifecycle = runCatching { ProcessDeathProbe.consumeAfterRestart(this) }
            .getOrElse { "process-death probe=FAIL: ${it.javaClass.simpleName}" }
        val result = runCatching { runNonInteractiveChecks() }
            .fold(
                onSuccess = {
                    "PASS: identity, AES wrapping, and JNI/COSE boundaries\n$it\n$lifecycle"
                },
                onFailure = { "FAIL: ${it.javaClass.simpleName}" },
            )
        status = TextView(this).apply {
            text = "C-007-R6 disposable boundary harness\n\n$result\n\nApproval-key user-presence is a separate manual ceremony."
            textSize = 18f
            setPadding(32, 48, 32, 32)
        }
        val approval = Button(this).apply {
            text = "Test approval signature"
            isEnabled = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P
            setOnClickListener { runApprovalCeremony() }
        }
        val processDeath = Button(this).apply {
            text = "Arm process-death test"
            setOnClickListener { armProcessDeathProbe() }
        }
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(status, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ))
            addView(processDeath)
            addView(approval)
        })
    }

    private fun armProcessDeathProbe() {
        runCatching { ProcessDeathProbe.arm(this) }
            .fold(
                onSuccess = {
                    status.append(
                        "\nPROCESS-DEATH ARMED: force-stop and relaunch the app; " +
                            "do not clear app data.",
                    )
                },
                onFailure = {
                    status.append("\nPROCESS-DEATH FAIL: ${it.javaClass.simpleName}")
                },
            )
    }

    private fun runApprovalCeremony() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.P) return
        val signature = runCatching { AndroidKeyStoreBoundary.initializedApprovalSignature() }
            .getOrElse {
                status.append("\nAPPROVAL FAIL: ${it.javaClass.simpleName}")
                return
            }
        runCatching {
            BiometricPrompt.Builder(this)
                .setTitle("Authorize synthetic C-007-R6 test")
                .setDescription("No command or repository data is signed.")
                .setNegativeButton("Cancel", mainExecutor) { _, _ ->
                    status.append("\nAPPROVAL CANCELLED")
                }
                .build()
                .authenticate(
                    BiometricPrompt.CryptoObject(signature),
                    CancellationSignal(),
                    mainExecutor,
                    object : BiometricPrompt.AuthenticationCallback() {
                        override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                            runCatching {
                                val authenticated = checkNotNull(result.cryptoObject?.signature)
                                val input = "C-007-R6-user-presence".encodeToByteArray()
                                try {
                                    AndroidKeyStoreBoundary.finishSignature(authenticated, input).fill(0)
                                } finally {
                                    input.fill(0)
                                }
                            }.fold(
                                onSuccess = {
                                    status.append("\nAPPROVAL PASS: one authenticated signature")
                                },
                                onFailure = {
                                    status.append("\nAPPROVAL FAIL: ${it.javaClass.simpleName}")
                                },
                            )
                        }

                        override fun onAuthenticationError(code: Int, message: CharSequence) {
                            status.append("\nAPPROVAL ERROR: code $code")
                        }
                    },
                )
        }.onFailure {
            status.append("\nAPPROVAL FAIL: ${it.javaClass.simpleName}")
        }
    }

    private fun runNonInteractiveChecks(): String {
        val identity = AndroidKeyStoreBoundary.ensureSigningKey(
            AndroidKeyStoreBoundary.SigningPurpose.IDENTITY,
        )
        val approval = AndroidKeyStoreBoundary.ensureSigningKey(
            AndroidKeyStoreBoundary.SigningPurpose.APPROVAL,
        )

        val protected = ByteArray(38).apply {
            byteArrayOf(0xa2.toByte(), 0x01, 0x26, 0x04, 0x58, 0x20).copyInto(this)
            SecureRandom().nextBytes(this, 6, size)
        }
        val exactSigStructure = "C-007-R6-JCA-boundary".encodeToByteArray()
        val der = AndroidKeyStoreBoundary.signIdentity(exactSigStructure)
        check(NativeCrypto.coseFromDer(protected, der).isNotEmpty())
        der.fill(0)
        exactSigStructure.fill(0)

        val keyId = "01".repeat(32)
        val aad = "conatus-spike-wrapped-key-aad".encodeToByteArray()
        val secret = ByteArray(32).also(SecureRandom()::nextBytes)
        val expected = secret.copyOf()
        val wrapped = AndroidKeyStoreBoundary.wrapAndDestroy(keyId, aad, secret)
        check(secret.all { it == 0.toByte() })
        val recovered = AndroidKeyStoreBoundary.unwrap(keyId, aad, wrapped)
        check(recovered.contentEquals(expected))
        expected.fill(0)
        recovered.fill(0)
        aad.fill(0)
        return "identity=${identity.summary()}; approval=${approval.summary()}"
    }

    private fun AndroidKeyStoreBoundary.KeyPosture.summary(): String =
        securityLevel?.let { "security-level-$it" }
            ?: if (insideSecureHardware) "hardware-backed" else "software-backed"

    private fun SecureRandom.nextBytes(target: ByteArray, from: Int, to: Int) {
        val random = ByteArray(to - from).also(::nextBytes)
        random.copyInto(target, from)
        random.fill(0)
    }
}

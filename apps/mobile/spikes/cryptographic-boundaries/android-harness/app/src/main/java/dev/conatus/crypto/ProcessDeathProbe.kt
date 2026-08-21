// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

package dev.conatus.crypto

import android.content.Context
import android.util.Base64
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.UUID

/**
 * Disposable lifecycle probe. It persists only a synthetic ciphertext, its
 * digest, and a random process-instance marker. Application backup is disabled
 * by the harness manifest and backup rules.
 */
internal object ProcessDeathProbe {
    private const val PREFERENCES = "c007_r6_process_death_probe"
    private const val ARMED = "armed"
    private const val PROCESS_INSTANCE = "process_instance"
    private const val FORMAT_VERSION = "format_version"
    private const val IV = "iv"
    private const val CIPHERTEXT = "ciphertext"
    private const val EXPECTED_DIGEST = "expected_digest"
    private const val VERSION = 1
    private const val KEY_ID =
        "0202020202020202020202020202020202020202020202020202020202020202"
    private const val MAX_ENCODED_FIELD_BYTES = 256

    private val currentProcessInstance = UUID.randomUUID().toString()

    fun arm(context: Context) {
        val secret = ByteArray(32).also(SecureRandom()::nextBytes)
        val aad = "C-007-R6-process-death-wrapped-fixture-v1".encodeToByteArray()
        var expectedDigest: ByteArray? = null
        var wrapped: AndroidKeyStoreBoundary.WrappedSecret? = null
        try {
            expectedDigest = MessageDigest.getInstance("SHA-256").digest(secret)
            wrapped = AndroidKeyStoreBoundary.wrapAndDestroy(KEY_ID, aad, secret)
            check(
                preferences(context).edit()
                    .clear()
                    .putBoolean(ARMED, true)
                    .putString(PROCESS_INSTANCE, currentProcessInstance)
                    .putInt(FORMAT_VERSION, wrapped.version)
                    .putString(IV, encode(wrapped.iv))
                    .putString(CIPHERTEXT, encode(wrapped.ciphertextAndTag))
                    .putString(EXPECTED_DIGEST, encode(expectedDigest))
                    .commit(),
            ) { "process-death probe state was not committed" }
        } finally {
            secret.fill(0)
            expectedDigest?.fill(0)
            aad.fill(0)
            wrapped?.iv?.fill(0)
            wrapped?.ciphertextAndTag?.fill(0)
        }
    }

    fun consumeAfterRestart(context: Context): String {
        val preferences = preferences(context)
        if (!preferences.getBoolean(ARMED, false)) {
            return "process-death probe=not armed"
        }
        if (preferences.getString(PROCESS_INSTANCE, null) == currentProcessInstance) {
            return "process-death probe=armed; terminate and relaunch"
        }

        var iv: ByteArray? = null
        var ciphertext: ByteArray? = null
        var expectedDigest: ByteArray? = null
        return try {
            val version = preferences.getInt(FORMAT_VERSION, -1)
            iv = decodeRequired(preferences.getString(IV, null), IV)
            ciphertext = decodeRequired(
                preferences.getString(CIPHERTEXT, null),
                CIPHERTEXT,
            )
            expectedDigest = decodeRequired(
                preferences.getString(EXPECTED_DIGEST, null),
                EXPECTED_DIGEST,
            )
            check(version == VERSION && iv.size == 12) { "invalid persisted format" }
            check(ciphertext.size == 48 && expectedDigest.size == 32) {
                "invalid persisted fixture size"
            }
            verifyWrappedFixture(version, iv, ciphertext, expectedDigest)
            verifyNativeReload()
            "process-death probe=PASS: wrapped fixture and JNI reload"
        } finally {
            iv?.fill(0)
            ciphertext?.fill(0)
            expectedDigest?.fill(0)
            check(preferences.edit().clear().commit()) {
                "process-death probe state was not cleared"
            }
        }
    }

    private fun verifyWrappedFixture(
        version: Int,
        iv: ByteArray,
        ciphertext: ByteArray,
        expectedDigest: ByteArray,
    ) {
        val aad = "C-007-R6-process-death-wrapped-fixture-v1".encodeToByteArray()
        var recovered: ByteArray? = null
        var actualDigest: ByteArray? = null
        try {
            recovered = AndroidKeyStoreBoundary.unwrap(
                KEY_ID,
                aad,
                AndroidKeyStoreBoundary.WrappedSecret(version, iv, ciphertext),
            )
            actualDigest = MessageDigest.getInstance("SHA-256").digest(recovered)
            check(MessageDigest.isEqual(expectedDigest, actualDigest)) {
                "wrapped fixture changed across process death"
            }
        } finally {
            aad.fill(0)
            recovered?.fill(0)
            actualDigest?.fill(0)
        }
    }

    private fun verifyNativeReload() {
        val protected = ByteArray(38).apply {
            byteArrayOf(0xa2.toByte(), 0x01, 0x26, 0x04, 0x58, 0x20).copyInto(this)
            fill(0x22, 6, size)
        }
        val signingInput = "C-007-R6-process-death-JNI-reload".encodeToByteArray()
        var der: ByteArray? = null
        var cose: ByteArray? = null
        try {
            der = AndroidKeyStoreBoundary.signIdentity(signingInput)
            cose = NativeCrypto.coseFromDer(protected, der)
            check(cose.size == 109) { "unexpected COSE boundary output" }
        } finally {
            protected.fill(0)
            signingInput.fill(0)
            der?.fill(0)
            cose?.fill(0)
        }
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    private fun encode(value: ByteArray): String =
        Base64.encodeToString(value, Base64.NO_WRAP)

    private fun decodeRequired(encoded: String?, name: String): ByteArray {
        require(!encoded.isNullOrEmpty() && encoded.length <= MAX_ENCODED_FIELD_BYTES) {
            "missing or oversized $name"
        }
        return Base64.decode(encoded, Base64.NO_WRAP)
    }
}

// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

package dev.conatus.crypto

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal object AndroidKeyStoreBoundary {
    private const val PROVIDER = "AndroidKeyStore"
    private const val IDENTITY_ALIAS = "conatus.spike.p256.identity.v1"
    private const val APPROVAL_ALIAS = "conatus.spike.p256.approval.v1"
    private const val WRAP_ALIAS_PREFIX = "conatus.spike.aes.wrap.v1."
    private const val MAX_SIGNED_BYTES = 1024 * 1024
    private const val MAX_SECRET_BYTES = 4096
    private const val GCM_TAG_BITS = 128

    enum class SigningPurpose { IDENTITY, APPROVAL }

    data class KeyPosture(
        val insideSecureHardware: Boolean,
        val securityLevel: Int?,
    )

    data class WrappedSecret(
        val version: Int,
        val iv: ByteArray,
        val ciphertextAndTag: ByteArray,
    )

    private fun keyStore(): KeyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }

    fun ensureSigningKey(purpose: SigningPurpose): KeyPosture {
        val alias = signingAlias(purpose)
        val store = keyStore()
        if (!store.containsAlias(alias)) {
            val builder = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                builder.setUnlockedDeviceRequired(true)
            }
            if (purpose == SigningPurpose.APPROVAL) {
                builder.setUserAuthenticationRequired(true)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    builder.setUserAuthenticationParameters(
                        0,
                        KeyProperties.AUTH_BIOMETRIC_STRONG,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    builder.setUserAuthenticationValidityDurationSeconds(-1)
                }
                builder.setInvalidatedByBiometricEnrollment(true)
            }
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, PROVIDER).run {
                initialize(builder.build())
                generateKeyPair()
            }
        }
        val privateKey = store.getKey(alias, null) as? PrivateKey
            ?: error("signing key unavailable")
        val keyInfo = KeyFactory.getInstance(privateKey.algorithm, PROVIDER)
            .getKeySpec(privateKey, KeyInfo::class.java)
        @Suppress("DEPRECATION")
        val insideSecureHardware = keyInfo.isInsideSecureHardware
        return KeyPosture(
            insideSecureHardware = insideSecureHardware,
            securityLevel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) keyInfo.securityLevel else null,
        )
    }

    fun initializedApprovalSignature(): Signature {
        ensureSigningKey(SigningPurpose.APPROVAL)
        return initializedSignature(SigningPurpose.APPROVAL)
    }

    fun finishSignature(signature: Signature, exactSigStructure: ByteArray): ByteArray {
        require(exactSigStructure.size <= MAX_SIGNED_BYTES) { "signed input too large" }
        signature.update(exactSigStructure)
        return signature.sign()
    }

    fun signIdentity(exactSigStructure: ByteArray): ByteArray {
        ensureSigningKey(SigningPurpose.IDENTITY)
        return finishSignature(initializedSignature(SigningPurpose.IDENTITY), exactSigStructure)
    }

    fun wrapAndDestroy(
        keyIdHex: String,
        canonicalAad: ByteArray,
        ownedPrivateKey: ByteArray,
    ): WrappedSecret {
        require(keyIdHex.length == 64 && keyIdHex.all { it in '0'..'9' || it in 'a'..'f' }) {
            "key ID must be lowercase hexadecimal"
        }
        require(ownedPrivateKey.size in 1..MAX_SECRET_BYTES) { "invalid private-key length" }
        require(canonicalAad.size <= MAX_SIGNED_BYTES) { "AAD too large" }
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, ensureDedicatedWrappingKey(keyIdHex))
            cipher.updateAAD(canonicalAad)
            return WrappedSecret(1, cipher.iv.copyOf(), cipher.doFinal(ownedPrivateKey))
        } finally {
            ownedPrivateKey.fill(0)
        }
    }

    fun unwrap(
        keyIdHex: String,
        canonicalAad: ByteArray,
        wrapped: WrappedSecret,
    ): ByteArray {
        require(wrapped.version == 1 && wrapped.iv.size == 12) { "unsupported wrapped-key format" }
        val key = keyStore().getKey(wrappingAlias(keyIdHex), null) as? SecretKey
            ?: error("wrapping key unavailable")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, wrapped.iv))
        cipher.updateAAD(canonicalAad)
        return cipher.doFinal(wrapped.ciphertextAndTag)
    }

    private fun initializedSignature(purpose: SigningPurpose): Signature {
        val privateKey = keyStore().getKey(signingAlias(purpose), null) as? PrivateKey
            ?: error("signing key unavailable")
        return Signature.getInstance("SHA256withECDSA").apply { initSign(privateKey) }
    }

    private fun ensureDedicatedWrappingKey(keyIdHex: String): SecretKey {
        val alias = wrappingAlias(keyIdHex)
        val store = keyStore()
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        val specification = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER).run {
            init(specification)
            generateKey()
        }
    }

    private fun signingAlias(purpose: SigningPurpose): String = when (purpose) {
        SigningPurpose.IDENTITY -> IDENTITY_ALIAS
        SigningPurpose.APPROVAL -> APPROVAL_ALIAS
    }

    private fun wrappingAlias(keyIdHex: String): String {
        require(keyIdHex.length == 64 && keyIdHex.all { character ->
            character in '0'..'9' || character in 'a'..'f'
        }) { "key ID must be lowercase hexadecimal" }
        return WRAP_ALIAS_PREFIX + keyIdHex
    }
}

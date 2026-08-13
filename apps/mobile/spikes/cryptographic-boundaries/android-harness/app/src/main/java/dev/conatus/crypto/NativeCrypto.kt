// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

package dev.conatus.crypto

internal object NativeCrypto {
    const val EXPECTED_API_VERSION = 1
    const val MAX_INPUT_BYTES = 1024 * 1024

    init {
        System.loadLibrary("conatus_crypto_boundary_spike")
        check(nativeApiVersion() == EXPECTED_API_VERSION) { "incompatible native crypto boundary" }
    }

    fun coseFromDer(protectedHeader: ByteArray, derSignature: ByteArray): ByteArray {
        require(protectedHeader.size <= MAX_INPUT_BYTES && derSignature.size <= MAX_INPUT_BYTES) {
            "native crypto input too large"
        }
        return checkNotNull(nativeCoseFromDer(protectedHeader, derSignature)) {
            "native crypto boundary rejected input"
        }
    }

    @JvmStatic private external fun nativeApiVersion(): Int
    @JvmStatic private external fun nativeCoseFromDer(
        protectedHeader: ByteArray,
        derSignature: ByteArray,
    ): ByteArray?
}

// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

package dev.conatus.crypto

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Synthetic, non-destructive checks against the actual Java/JNI boundary. */
internal object JniNegativeBoundaryChecks {
    private const val THREAD_COUNT = 4
    private const val CALLS_PER_THREAD = 64
    private val minimalDer = byteArrayOf(
        0x30,
        0x06,
        0x02,
        0x01,
        0x01,
        0x02,
        0x01,
        0x01,
    )

    fun run(): String {
        var rejected = 0
        val protected = canonicalProtectedHeader()
        try {
            for (length in 0..80) {
                val malformed = ByteArray(length) { 0x30 }
                try {
                    rejectWithoutMutation(protected, malformed)
                    rejected += 1
                } finally {
                    malformed.fill(0)
                }
            }

            val explicitMalformed = arrayOf(
                byteArrayOf(0x30, 0x07, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01),
                byteArrayOf(0x30, 0x06, 0x02, 0x01, 0x00, 0x02, 0x01, 0x01),
                byteArrayOf(0x30, 0x06, 0x02, 0x01, 0x80.toByte(), 0x02, 0x01, 0x01),
                byteArrayOf(0x30, 0x07, 0x02, 0x02, 0x00, 0x01, 0x02, 0x01, 0x01),
                byteArrayOf(0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x00),
            )
            try {
                explicitMalformed.forEach {
                    rejectWithoutMutation(protected, it)
                    rejected += 1
                }
            } finally {
                explicitMalformed.forEach { it.fill(0) }
            }

            val invalidHeaders = arrayOf(
                ByteArray(0),
                protected.copyOf().also { it[0] = 0xa1.toByte() },
                protected.copyOf().also { it[2] = 0x27 },
                protected.copyOf(37),
            )
            try {
                invalidHeaders.forEach {
                    rejectWithoutMutation(it, minimalDer)
                    rejected += 1
                }
            } finally {
                invalidHeaders.forEach { it.fill(0) }
            }

            val oversized = ByteArray(NativeCrypto.MAX_INPUT_BYTES + 1)
            try {
                rejectWithoutMutation(oversized, minimalDer)
                rejected += 1
                rejectWithoutMutation(protected, oversized)
                rejected += 1
                check(
                    runCatching { NativeCrypto.coseFromDer(oversized, minimalDer) }
                        .exceptionOrNull() is IllegalArgumentException,
                ) { "Kotlin JNI size guard did not fail closed" }
            } finally {
                oversized.fill(0)
            }

            check(
                runCatching { NativeCrypto.coseFromDer(protected, ByteArray(0)) }
                    .exceptionOrNull() is IllegalStateException,
            ) { "Kotlin JNI rejection was not stable" }

            runConcurrentCalls()
            acceptAfterRejection(protected)
        } finally {
            protected.fill(0)
        }
        return "JNI-negative=PASS: $rejected rejects; " +
            "${THREAD_COUNT * CALLS_PER_THREAD} concurrent calls; recovery"
    }

    private fun rejectWithoutMutation(protected: ByteArray, der: ByteArray) {
        val protectedBefore = protected.copyOf()
        val derBefore = der.copyOf()
        var output: ByteArray? = null
        try {
            output = NativeCrypto.rawCoseFromDerForHarness(protected, der)
            check(output == null) { "malformed JNI input was accepted" }
            check(protected.contentEquals(protectedBefore)) { "Java protected input changed" }
            check(der.contentEquals(derBefore)) { "Java DER input changed" }
        } finally {
            output?.fill(0)
            protectedBefore.fill(0)
            derBefore.fill(0)
        }
    }

    private fun acceptAfterRejection(protected: ByteArray) {
        val output = checkNotNull(
            NativeCrypto.rawCoseFromDerForHarness(protected, minimalDer),
        ) { "valid JNI recovery input was rejected" }
        try {
            check(output.size == 109) { "unexpected JNI recovery output" }
            check(
                output[0] == 0x84.toByte() &&
                    output[1] == 0x58.toByte() &&
                    output[2] == 0x26.toByte(),
            ) {
                "unexpected JNI recovery prefix"
            }
        } finally {
            output.fill(0)
        }
    }

    private fun runConcurrentCalls() {
        val ready = CountDownLatch(THREAD_COUNT)
        val start = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(THREAD_COUNT)
        try {
            val futures = (0 until THREAD_COUNT).map { thread ->
                executor.submit {
                    val protected = canonicalProtectedHeader()
                    val invalid = byteArrayOf(0x30, thread.toByte())
                    try {
                        ready.countDown()
                        check(start.await(5, TimeUnit.SECONDS)) { "concurrent JNI start timeout" }
                        repeat(CALLS_PER_THREAD) { call ->
                            val output = if ((thread + call) % 2 == 0) {
                                NativeCrypto.rawCoseFromDerForHarness(protected, minimalDer)
                            } else {
                                NativeCrypto.rawCoseFromDerForHarness(protected, invalid)
                            }
                            try {
                                if ((thread + call) % 2 == 0) {
                                    check(output?.size == 109) { "concurrent valid JNI call failed" }
                                } else {
                                    check(output == null) { "concurrent malformed JNI call succeeded" }
                                }
                            } finally {
                                output?.fill(0)
                            }
                        }
                    } finally {
                        protected.fill(0)
                        invalid.fill(0)
                    }
                }
            }
            check(ready.await(5, TimeUnit.SECONDS)) { "concurrent JNI workers did not start" }
            start.countDown()
            futures.forEach { it.get(10, TimeUnit.SECONDS) }
        } finally {
            start.countDown()
            executor.shutdownNow()
            check(executor.awaitTermination(5, TimeUnit.SECONDS)) {
                "concurrent JNI workers did not terminate"
            }
        }
    }

    private fun canonicalProtectedHeader(): ByteArray = ByteArray(38).apply {
        byteArrayOf(0xa2.toByte(), 0x01, 0x26, 0x04, 0x58, 0x20).copyInto(this)
        fill(0x33, 6, size)
    }
}

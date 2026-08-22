// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

package dev.conatus.crypto

import android.app.Activity
import android.content.Context
import android.os.Bundle
import java.io.File
import java.io.FileOutputStream

internal object JniCrashProbe {
    private const val INVOKED_MARKER = "c007-r6-jni-abort-invoked"
    private const val RETURNED_MARKER = "c007-r6-jni-abort-returned"

    enum class Result { Pending, Passed, Failed }

    fun reset(context: Context) {
        val invoked = marker(context, INVOKED_MARKER)
        val returned = marker(context, RETURNED_MARKER)
        check(!invoked.exists() || invoked.delete())
        check(!returned.exists() || returned.delete())
    }

    fun consume(context: Context): Result {
        val invoked = marker(context, INVOKED_MARKER)
        val returned = marker(context, RETURNED_MARKER)
        val result = when {
            returned.exists() -> Result.Failed
            invoked.exists() -> Result.Passed
            else -> Result.Pending
        }
        if (result != Result.Pending) reset(context)
        return result
    }

    fun recordInvoked(context: Context) = writeAndSync(marker(context, INVOKED_MARKER))

    fun recordUnexpectedReturn(context: Context) = writeAndSync(marker(context, RETURNED_MARKER))

    private fun marker(context: Context, name: String) = File(context.filesDir, name)

    private fun writeAndSync(file: File) {
        FileOutputStream(file, false).use { output ->
            output.write(byteArrayOf(1))
            output.fd.sync()
        }
    }
}

/** Runs in `:jni_crash_probe`; the main activity never calls abort directly. */
class JniCrashProbeActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        JniCrashProbe.recordInvoked(this)
        try {
            NativeCrypto.abortIsolatedProcessForHarness()
        } catch (_: Throwable) {
            JniCrashProbe.recordUnexpectedReturn(this)
            finish()
        }
    }
}

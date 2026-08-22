// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

package dev.conatus.crypto

import android.app.Activity
import android.content.Context
import android.os.Bundle
import android.os.Process
import java.io.File
import java.io.FileOutputStream

internal object JniCrashProbe {
    private const val INVOKED_MARKER = "c007-r6-jni-abort-invoked"
    private const val RETURNED_MARKER = "c007-r6-jni-abort-returned"
    private const val PARENT_PID_MARKER = "c007-r6-jni-parent-pid"

    enum class Result {
        NotArmed,
        Pending,
        Passed,
        NativeReturned,
        ParentRestarted,
        InvalidState,
    }

    fun reset(context: Context) {
        val invoked = marker(context, INVOKED_MARKER)
        val returned = marker(context, RETURNED_MARKER)
        val parentPid = marker(context, PARENT_PID_MARKER)
        check(!invoked.exists() || invoked.delete())
        check(!returned.exists() || returned.delete())
        check(!parentPid.exists() || parentPid.delete())
    }

    fun arm(context: Context) {
        reset(context)
        writeAndSync(marker(context, PARENT_PID_MARKER), Process.myPid().toString().encodeToByteArray())
    }

    fun observe(context: Context): Result {
        val invoked = marker(context, INVOKED_MARKER)
        val returned = marker(context, RETURNED_MARKER)
        val parentPid = marker(context, PARENT_PID_MARKER)
        val result = when {
            !parentPid.exists() && (invoked.exists() || returned.exists()) -> Result.InvalidState
            !parentPid.exists() -> Result.NotArmed
            readParentPid(parentPid) != Process.myPid() -> Result.ParentRestarted
            returned.exists() -> Result.NativeReturned
            invoked.exists() -> Result.Passed
            else -> Result.Pending
        }
        if (result != Result.NotArmed && result != Result.Pending) reset(context)
        return result
    }

    fun recordInvoked(context: Context) = writeAndSync(marker(context, INVOKED_MARKER), byteArrayOf(1))

    fun recordUnexpectedReturn(context: Context) =
        writeAndSync(marker(context, RETURNED_MARKER), byteArrayOf(1))

    private fun marker(context: Context, name: String) = File(context.filesDir, name)

    private fun readParentPid(file: File): Int? =
        runCatching { file.readText(Charsets.US_ASCII).toInt() }.getOrNull()

    private fun writeAndSync(file: File, value: ByteArray) {
        FileOutputStream(file, false).use { output ->
            output.write(value)
            output.fd.sync()
        }
        value.fill(0)
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

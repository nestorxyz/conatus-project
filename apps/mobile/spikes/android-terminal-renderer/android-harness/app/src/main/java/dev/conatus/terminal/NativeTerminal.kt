// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

package dev.conatus.terminal

import java.io.Closeable

internal class NativeTerminal(columns: Int, screenLines: Int) : Closeable {
    private var handle = nativeCreate(columns, screenLines).requireSuccess("create")

    fun feed(bytes: ByteArray): Long = nativeFeed(currentHandle(), bytes).requireSuccess("feed")

    fun resize(columns: Int, screenLines: Int): Long =
        nativeResize(currentHandle(), columns, screenLines).requireSuccess("resize")

    fun snapshot(): TerminalSnapshot =
        TerminalSnapshot.decode(checkNotNull(nativeSnapshot(currentHandle())) { "snapshot failed" })

    override fun close() {
        val activeHandle = handle
        if (activeHandle > 0) {
            nativeDestroy(activeHandle).requireSuccess("destroy")
            handle = 0
        }
    }

    private fun currentHandle(): Long = check(handle > 0) { "terminal is closed" }.let { handle }

    private fun Long.requireSuccess(operation: String): Long =
        also { check(it >= 0) { "$operation failed with native status $it" } }

    private companion object {
        init {
            System.loadLibrary("conatus_android_terminal_spike")
        }

        @JvmStatic external fun nativeCreate(columns: Int, screenLines: Int): Long
        @JvmStatic external fun nativeDestroy(handle: Long): Long
        @JvmStatic external fun nativeFeed(handle: Long, bytes: ByteArray): Long
        @JvmStatic external fun nativeResize(handle: Long, columns: Int, screenLines: Int): Long
        @JvmStatic external fun nativeSnapshot(handle: Long): ByteArray?
    }
}

// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

package dev.conatus.terminal

import java.nio.ByteBuffer
import java.nio.ByteOrder

internal data class TerminalSnapshot(
    val generation: Long,
    val columns: Int,
    val screenLines: Int,
    val rows: List<List<TerminalCell>>,
    val strippedHyperlinkCells: Long,
) {
    companion object {
        private const val MAX_SNAPSHOT_BYTES = 4 * 1024 * 1024

        fun decode(bytes: ByteArray): TerminalSnapshot {
            require(bytes.size in 22..MAX_SNAPSHOT_BYTES) { "invalid snapshot size" }
            val input = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            require(input.readBytes(4).contentEquals("CTRM".encodeToByteArray())) { "bad header" }
            require(input.short.toInt().toUShort().toInt() == 1) { "unsupported version" }

            val generation = input.long
            val columns = input.unsignedShort()
            val screenLines = input.unsignedShort()
            val strippedHyperlinks = input.int.toUInt().toLong()
            require(columns in 1..512 && screenLines in 1..256) { "invalid dimensions" }

            val rows = List(screenLines) {
                val cellCount = input.unsignedShort()
                require(cellCount <= columns) { "row exceeds columns" }
                List(cellCount) { input.readCell() }
            }
            require(!input.hasRemaining()) { "trailing snapshot bytes" }

            return TerminalSnapshot(
                generation,
                columns,
                screenLines,
                rows,
                strippedHyperlinks,
            )
        }

        private fun ByteBuffer.readCell(): TerminalCell {
            val codePoint = int
            require(Character.isValidCodePoint(codePoint)) { "invalid code point" }
            val flags = unsignedShort()
            val foreground = readColor()
            val background = readColor()
            val combiningLength = unsignedShort()
            require(combiningLength <= remaining()) { "truncated combining text" }
            val combining = readBytes(combiningLength).decodeToString(throwOnInvalidSequence = true)
            return TerminalCell(codePoint, combining, foreground, background, flags)
        }

        private fun ByteBuffer.readColor(): TerminalColor = when (get().toInt()) {
            0 -> TerminalColor.Named(unsignedShort())
            1 -> TerminalColor.Indexed(get().toInt().and(0xff)).also { get() }
            2 -> TerminalColor.Rgb(
                get().toInt().and(0xff),
                get().toInt().and(0xff),
                get().toInt().and(0xff),
            )
            else -> error("unknown color type")
        }

        private fun ByteBuffer.unsignedShort(): Int = short.toInt().and(0xffff)

        private fun ByteBuffer.readBytes(length: Int): ByteArray =
            ByteArray(length).also(::get)
    }
}

internal data class TerminalCell(
    val codePoint: Int,
    val combining: String,
    val foreground: TerminalColor,
    val background: TerminalColor,
    val flags: Int,
) {
    val isWideCharacterSpacer: Boolean
        get() = flags.and(WIDE_CHARACTER_SPACER) != 0

    val text: String
        get() = String(Character.toChars(codePoint)) + combining

    private companion object {
        const val WIDE_CHARACTER_SPACER = 0x40
    }
}

internal fun List<TerminalCell>.logicalText(): String =
    asSequence()
        .filterNot(TerminalCell::isWideCharacterSpacer)
        .joinToString(separator = "", transform = TerminalCell::text)

internal sealed interface TerminalColor {
    data class Named(val value: Int) : TerminalColor
    data class Indexed(val value: Int) : TerminalColor
    data class Rgb(val red: Int, val green: Int, val blue: Int) : TerminalColor
}

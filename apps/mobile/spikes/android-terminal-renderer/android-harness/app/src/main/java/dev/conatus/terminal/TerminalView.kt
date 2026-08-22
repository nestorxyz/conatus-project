// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

package dev.conatus.terminal

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.text.InputType
import android.util.AttributeSet
import android.util.TypedValue
import android.view.MotionEvent
import android.view.View
import android.view.accessibility.AccessibilityManager
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import kotlin.math.abs
import kotlin.math.floor

internal class TerminalView @JvmOverloads constructor(
    context: Context,
    attributes: AttributeSet? = null,
) : View(context, attributes) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(232, 238, 242)
        typeface = Typeface.MONOSPACE
        textSize = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP,
            16f,
            resources.displayMetrics,
        )
    }
    private var snapshot: TerminalSnapshot? = null
    private var selectedRow: Int? = null
    private var lastGestureY = 0f
    private var gestureMoved = false
    private val accessibilityManager = context.getSystemService(AccessibilityManager::class.java)
    var onTextInput: ((String) -> Unit)? = null
    var onScrollLines: ((Int) -> TerminalSnapshot?)? = null

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        setBackgroundColor(Color.rgb(16, 20, 24))
    }

    fun show(value: TerminalSnapshot) {
        val previous = snapshot
        if (previous != null && value.generation < previous.generation) return
        if (previous?.generation != value.generation) selectedRow = null
        snapshot = value
        contentDescription = accessibleText(value)
        invalidate()
        sendAccessibilityEvent(android.view.accessibility.AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED)
    }

    fun replace(value: TerminalSnapshot) {
        snapshot = null
        selectedRow = null
        show(value)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val current = snapshot ?: return
        val metrics = paint.fontMetrics
        val lineHeight = metrics.descent - metrics.ascent
        current.rows.forEachIndexed { rowIndex, row ->
            if (selectedRow == rowIndex) {
                paint.color = Color.rgb(48, 73, 83)
                canvas.drawRect(0f, rowIndex * lineHeight, width.toFloat(), (rowIndex + 1) * lineHeight, paint)
            }
            paint.color = Color.rgb(232, 238, 242)
            val baseline = rowIndex * lineHeight - metrics.ascent
            canvas.drawText(row.logicalText(), 0f, baseline, paint)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val lineHeight = paint.fontMetrics.run { descent - ascent }
        return when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                requestFocus()
                lastGestureY = event.y
                gestureMoved = false
                true
            }
            MotionEvent.ACTION_MOVE -> {
                val lineDelta = ((event.y - lastGestureY) / lineHeight).toInt()
                if (lineDelta != 0) {
                    gestureMoved = true
                    lastGestureY += lineDelta * lineHeight
                    onScrollLines?.invoke(lineDelta)?.let(::show)
                }
                true
            }
            MotionEvent.ACTION_UP -> {
                if (!gestureMoved && abs(event.y - lastGestureY) < lineHeight) {
                    selectedRow = floor(event.y / lineHeight)
                        .toInt()
                        .coerceIn(0, (snapshot?.screenLines ?: 1) - 1)
                    announceSelectionForAccessibility()
                    invalidate()
                }
                performClick()
                true
            }
            MotionEvent.ACTION_CANCEL -> {
                gestureMoved = false
                true
            }
            else -> true
        }
    }

    override fun performClick(): Boolean = super.performClick()

    @Suppress("DEPRECATION") // Required for the API-26 baseline; guarded and verified with TalkBack.
    private fun announceSelectionForAccessibility() {
        if (!accessibilityManager.isEnabled) return
        runCatching { announceForAccessibility(selectedText()) }
    }

    override fun onCheckIsTextEditor(): Boolean = true

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        outAttrs.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI
        return object : BaseInputConnection(this, false) {
            override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean {
                text?.toString()?.let { onTextInput?.invoke(it) }
                return true
            }
        }
    }

    fun selectedText(): String = selectedRow
        ?.let { snapshot?.rows?.getOrNull(it) }
        ?.logicalText()
        ?.trimEnd()
        .orEmpty()

    private fun accessibleText(value: TerminalSnapshot): String = value.rows
        .joinToString(separator = "\n") { row -> row.logicalText().trimEnd() }
        .trimEnd()
}

// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

package dev.conatus.terminal

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import android.os.Bundle
import android.text.InputType
import android.util.AttributeSet
import android.util.TypedValue
import android.view.MotionEvent
import android.view.View
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityNodeProvider
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.widget.TextView
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
    private var accessibilityFocusedRow: Int? = null
    private val accessibilityManager = context.getSystemService(AccessibilityManager::class.java)
    private val terminalNodeProvider = TerminalNodeProvider()
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
        accessibilityFocusedRow = null
        snapshot = value
        contentDescription = null
        invalidate()
        sendAccessibilityEvent(AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED)
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

    override fun getAccessibilityNodeProvider(): AccessibilityNodeProvider = terminalNodeProvider

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

    private fun rowText(row: Int): String? = snapshot
        ?.rows
        ?.getOrNull(row)
        ?.logicalText()
        ?.trimEnd()
        ?.takeIf(String::isNotEmpty)

    private fun visibleRowIds(): List<Int> = snapshot
        ?.rows
        ?.indices
        ?.filter { rowText(it) != null }
        .orEmpty()

    private fun rowBounds(row: Int): Rect {
        val lineHeight = paint.fontMetrics.run { descent - ascent }
        return Rect(0, (row * lineHeight).toInt(), width, ((row + 1) * lineHeight).toInt())
    }

    @Suppress("DEPRECATION") // AccessibilityEvent.obtain is required on the API-26 baseline.
    private fun sendVirtualEvent(row: Int, type: Int) {
        val text = rowText(row) ?: return
        if (!accessibilityManager.isEnabled) return
        runCatching {
            val event = AccessibilityEvent.obtain(type).apply {
                packageName = context.packageName
                className = TextView::class.java.name
                this.text.add(text)
                setSource(this@TerminalView, row)
            }
            parent?.requestSendAccessibilityEvent(this, event)
        }
    }

    @Suppress("DEPRECATION") // API-26 node factories/actions remain required for the supported baseline.
    private inner class TerminalNodeProvider : AccessibilityNodeProvider() {
        override fun createAccessibilityNodeInfo(virtualViewId: Int): AccessibilityNodeInfo? =
            if (virtualViewId == AccessibilityNodeProvider.HOST_VIEW_ID) {
                hostNode()
            } else {
                rowNode(virtualViewId)
            }

        override fun findAccessibilityNodeInfosByText(
            searched: String,
            virtualViewId: Int,
        ): List<AccessibilityNodeInfo> = visibleRowIds()
            .filter { rowText(it)?.contains(searched, ignoreCase = true) == true }
            .mapNotNull(::rowNode)

        override fun findFocus(focus: Int): AccessibilityNodeInfo? =
            if (focus == AccessibilityNodeInfo.FOCUS_ACCESSIBILITY) {
                accessibilityFocusedRow?.let(::rowNode)
            } else {
                null
            }

        override fun performAction(virtualViewId: Int, action: Int, arguments: Bundle?): Boolean {
            if (virtualViewId == AccessibilityNodeProvider.HOST_VIEW_ID) return false
            if (rowText(virtualViewId) == null) return false
            return when (action) {
                AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS -> {
                    accessibilityFocusedRow?.takeIf { it != virtualViewId }?.let {
                        sendVirtualEvent(it, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUS_CLEARED)
                    }
                    accessibilityFocusedRow = virtualViewId
                    sendVirtualEvent(virtualViewId, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED)
                    true
                }
                AccessibilityNodeInfo.ACTION_CLEAR_ACCESSIBILITY_FOCUS -> {
                    if (accessibilityFocusedRow != virtualViewId) return false
                    accessibilityFocusedRow = null
                    sendVirtualEvent(virtualViewId, AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUS_CLEARED)
                    true
                }
                AccessibilityNodeInfo.ACTION_CLICK -> {
                    selectedRow = virtualViewId
                    invalidate()
                    sendVirtualEvent(virtualViewId, AccessibilityEvent.TYPE_VIEW_SELECTED)
                    true
                }
                else -> false
            }
        }

        private fun hostNode(): AccessibilityNodeInfo =
            AccessibilityNodeInfo.obtain(this@TerminalView).apply {
                className = TerminalView::class.java.name
                contentDescription = null
                isFocusable = false
                visibleRowIds().forEach { addChild(this@TerminalView, it) }
            }

        private fun rowNode(row: Int): AccessibilityNodeInfo? {
            val text = rowText(row) ?: return null
            val parentBounds = rowBounds(row)
            val screenBounds = Rect(parentBounds)
            val location = IntArray(2)
            getLocationOnScreen(location)
            screenBounds.offset(location[0], location[1])

            return AccessibilityNodeInfo.obtain().apply {
                packageName = context.packageName
                className = TextView::class.java.name
                setSource(this@TerminalView, row)
                setParent(this@TerminalView)
                this.text = text
                isEnabled = true
                isFocusable = true
                isClickable = true
                isVisibleToUser = this@TerminalView.visibility == VISIBLE && this@TerminalView.isShown
                isAccessibilityFocused = accessibilityFocusedRow == row
                isSelected = selectedRow == row
                setBoundsInParent(parentBounds)
                setBoundsInScreen(screenBounds)
                addAction(
                    if (accessibilityFocusedRow == row) {
                        AccessibilityNodeInfo.ACTION_CLEAR_ACCESSIBILITY_FOCUS
                    } else {
                        AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS
                    },
                )
                addAction(AccessibilityNodeInfo.ACTION_CLICK)
            }
        }
    }
}

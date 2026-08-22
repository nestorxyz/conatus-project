// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

package dev.conatus.terminal

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import java.util.Locale
import kotlin.concurrent.thread
import kotlin.system.measureTimeMillis

class MainActivity : ComponentActivity() {
    private var interactiveTerminal: NativeTerminal? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                var status by remember { mutableStateOf("Ready") }
                var terminalView by remember { mutableStateOf<TerminalView?>(null) }

                Column(
                    modifier = Modifier.fillMaxSize().padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text("C-008 native terminal spike", color = Color.White)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = {
                            status = "Running corpus…"
                            runCorpus(terminalView) { status = it }
                        }) { Text("Run corpus") }
                        Button(onClick = { status = "Selected: ${terminalView?.selectedText().orEmpty()}" }) {
                            Text("Inspect selection")
                        }
                    }
                    Text(status, color = Color.White)
                    AndroidView(
                        modifier = Modifier.fillMaxWidth().weight(1f),
                        factory = { context ->
                            TerminalView(context).also { view ->
                                view.onScrollLines = { delta ->
                                    interactiveTerminal?.run {
                                        scroll(delta)
                                        snapshot()
                                    }
                                }
                                terminalView = view
                            }
                        },
                    )
                }
            }
        }
    }

    private fun runCorpus(view: TerminalView?, report: (String) -> Unit) {
        thread(name = "terminal-corpus") {
            val rows = assets.open("manifest.tsv").bufferedReader().use { reader ->
                reader.lineSequence().drop(1).map { it.split('\t') }.toList()
            }
            var lastSnapshot: TerminalSnapshot? = null
            var retainedTerminal: NativeTerminal? = null
            var cases = 0
            runCatching {
                val duration = measureTimeMillis {
                    rows.forEach { fields ->
                        val terminal = NativeTerminal(80, 25)
                        try {
                            when (fields[2]) {
                                "hex" -> terminal.feed(fields[3].hexToBytes())
                                "generated" -> feedLongTrace(terminal)
                                else -> error("unknown encoding")
                            }
                            lastSnapshot = terminal.snapshot()
                            if (fields[0] == "long-scrollback") {
                                retainedTerminal = terminal
                            } else {
                                terminal.close()
                            }
                            cases += 1
                        } catch (failure: Throwable) {
                            terminal.close()
                            throw failure
                        }
                    }
                }
                runOnUiThread {
                    if (isDestroyed) {
                        retainedTerminal?.close()
                    } else {
                        interactiveTerminal?.close()
                        interactiveTerminal = retainedTerminal
                        lastSnapshot?.let { view?.show(it) }
                        report("$cases cases in $duration ms; no Android permissions requested")
                    }
                }
            }.onFailure { failure ->
                retainedTerminal?.close()
                runOnUiThread { report("FAIL: ${failure.javaClass.simpleName}") }
            }
        }
    }

    override fun onDestroy() {
        interactiveTerminal?.close()
        interactiveTerminal = null
        super.onDestroy()
    }

    private fun feedLongTrace(terminal: NativeTerminal) {
        val chunk = StringBuilder()
        repeat(10_000) { index ->
            val line = String.format(Locale.ROOT, "line-%05d-alpha-beta-gamma\r\n", index)
            if (chunk.length + line.length > 60_000) {
                terminal.feed(chunk.toString().encodeToByteArray())
                chunk.clear()
            }
            chunk.append(line)
        }
        if (chunk.isNotEmpty()) terminal.feed(chunk.toString().encodeToByteArray())
    }

    private fun String.hexToBytes(): ByteArray {
        require(length % 2 == 0)
        return ByteArray(length / 2) { index -> substring(index * 2, index * 2 + 2).toInt(16).toByte() }
    }
}

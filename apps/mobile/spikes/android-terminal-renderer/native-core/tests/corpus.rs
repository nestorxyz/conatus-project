// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

use std::fs;
use std::path::Path;

use conatus_android_terminal_spike::{EventAudit, MAX_INPUT_BYTES, TerminalCore};

#[test]
fn every_tracked_case_is_bounded_by_the_rust_core() {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR")).join("../corpus/manifest.tsv");
    let contents = fs::read_to_string(manifest).expect("tracked corpus manifest");

    for line in contents.lines().skip(1) {
        let fields: Vec<_> = line.split('\t').collect();
        assert_eq!(fields.len(), 6, "invalid manifest row");

        let id = fields[0];
        let encoding = fields[2];
        let payload = fields[3];
        let mut terminal = TerminalCore::new(80, 25).expect("valid terminal");

        match encoding {
            "hex" => {
                let bytes = decode_hex(payload).unwrap_or_else(|error| panic!("{id}: {error}"));
                terminal
                    .feed(&bytes)
                    .unwrap_or_else(|error| panic!("{id}: {error:?}"));
            }
            "generated" => feed_generated(&mut terminal, payload, id),
            other => panic!("{id}: unsupported encoding {other}"),
        }

        let snapshot = terminal.snapshot();
        assert_eq!(snapshot.columns, 80, "{id}");
        assert_eq!(snapshot.screen_lines, 25, "{id}");
        assert_eq!(snapshot.rows.len(), 25, "{id}");

        assert_no_privileged_event(id, terminal.event_audit());
    }
}

fn decode_hex(value: &str) -> Result<Vec<u8>, &'static str> {
    if !value.len().is_multiple_of(2) {
        return Err("odd hex payload length");
    }

    value
        .as_bytes()
        .chunks_exact(2)
        .map(|pair| {
            let text = std::str::from_utf8(pair).map_err(|_| "hex payload is not ASCII")?;
            u8::from_str_radix(text, 16).map_err(|_| "invalid hex payload")
        })
        .collect()
}

fn feed_generated(terminal: &mut TerminalCore, instruction: &str, id: &str) {
    assert_eq!(
        instruction, "10000-lines:line-%05d-alpha-beta-gamma-crlf",
        "{id}"
    );
    let mut chunk = Vec::with_capacity(MAX_INPUT_BYTES);

    for index in 0..10_000 {
        let line = format!("line-{index:05}-alpha-beta-gamma\r\n");
        if chunk.len() + line.len() > MAX_INPUT_BYTES {
            terminal
                .feed(&chunk)
                .unwrap_or_else(|error| panic!("{id}: {error:?}"));
            chunk.clear();
        }
        chunk.extend_from_slice(line.as_bytes());
    }

    if !chunk.is_empty() {
        terminal
            .feed(&chunk)
            .unwrap_or_else(|error| panic!("{id}: {error:?}"));
    }
}

fn assert_no_privileged_event(id: &str, audit: EventAudit) {
    assert_eq!(audit.clipboard_reads, 0, "{id}: clipboard read");
    assert_eq!(audit.clipboard_writes, 0, "{id}: clipboard write");
    // Parser replies stay in this in-memory aggregate and never cross JNI in
    // the disposable harness. Titles and bells are likewise only counters.
}

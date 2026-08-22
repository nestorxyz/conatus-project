// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Platform-neutral terminal core for the disposable C-008 Android spike.
//!
//! Rust owns untrusted-byte parsing and grid state. Android rendering and all
//! platform capabilities remain outside this crate. Snapshots are immutable and
//! generation-tagged so a later JNI wrapper can reject stale updates.

use std::sync::{Arc, Mutex};

use alacritty_terminal::Term;
use alacritty_terminal::event::{Event, EventListener};
use alacritty_terminal::grid::{Dimensions, Scroll};
use alacritty_terminal::term::cell::Flags;
use alacritty_terminal::term::{Config, Osc52};
use alacritty_terminal::vte::ansi::{Color, Processor};

mod jni_api;

/// Maximum PTY chunk accepted by one parser call.
pub const MAX_INPUT_BYTES: usize = 64 * 1024;

/// Maximum terminal columns accepted by the spike.
pub const MAX_COLUMNS: usize = 512;

/// Maximum terminal screen lines accepted by the spike.
pub const MAX_SCREEN_LINES: usize = 256;

/// Fixed C-008 scrollback limit.
pub const MAX_SCROLLBACK_LINES: usize = 10_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TerminalError {
    EmptyDimensions,
    DimensionsTooLarge,
    InputTooLarge,
    ScrollDeltaTooLarge,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CellColor {
    Named(u16),
    Indexed(u8),
    Rgb { red: u8, green: u8, blue: u8 },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CellSnapshot {
    pub character: char,
    pub combining: String,
    pub foreground: CellColor,
    pub background: CellColor,
    pub flags: u16,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScreenSnapshot {
    pub generation: u64,
    pub columns: usize,
    pub screen_lines: usize,
    pub rows: Vec<Vec<CellSnapshot>>,
    /// Hyperlink metadata is deliberately not copied into the snapshot.
    pub stripped_hyperlink_cells: usize,
}

impl ScreenSnapshot {
    /// Encode a stable, length-delimited JNI payload without platform actions
    /// or attacker-controlled metadata such as hyperlink targets.
    pub fn encode_binary(&self) -> Vec<u8> {
        let mut output = Vec::new();
        output.extend_from_slice(b"CTRM");
        output.extend_from_slice(&1_u16.to_le_bytes());
        output.extend_from_slice(&self.generation.to_le_bytes());
        output.extend_from_slice(&(self.columns as u16).to_le_bytes());
        output.extend_from_slice(&(self.screen_lines as u16).to_le_bytes());
        output.extend_from_slice(&(self.stripped_hyperlink_cells as u32).to_le_bytes());

        for row in &self.rows {
            output.extend_from_slice(&(row.len() as u16).to_le_bytes());
            for cell in row {
                output.extend_from_slice(&(cell.character as u32).to_le_bytes());
                output.extend_from_slice(&cell.flags.to_le_bytes());
                encode_color(&mut output, cell.foreground);
                encode_color(&mut output, cell.background);
                output.extend_from_slice(&(cell.combining.len() as u16).to_le_bytes());
                output.extend_from_slice(cell.combining.as_bytes());
            }
        }

        output
    }
}

/// Aggregate only: never retains title, clipboard, URL, or parser-reply text.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct EventAudit {
    pub title_requests: u64,
    pub clipboard_reads: u64,
    pub clipboard_writes: u64,
    pub parser_reply_bytes: u64,
    pub bell_requests: u64,
    pub wakeups: u64,
    pub other_events: u64,
}

#[derive(Clone, Default)]
struct AuditListener(Arc<Mutex<EventAudit>>);

impl AuditListener {
    fn snapshot(&self) -> EventAudit {
        *self
            .0
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

impl EventListener for AuditListener {
    fn send_event(&self, event: Event) {
        let mut audit = self
            .0
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        match event {
            Event::Title(_) | Event::ResetTitle => audit.title_requests += 1,
            Event::ClipboardLoad(_, _) => audit.clipboard_reads += 1,
            Event::ClipboardStore(_, _) => audit.clipboard_writes += 1,
            Event::PtyWrite(reply) => {
                audit.parser_reply_bytes =
                    audit.parser_reply_bytes.saturating_add(reply.len() as u64);
            }
            Event::Bell => audit.bell_requests += 1,
            Event::Wakeup => audit.wakeups += 1,
            _ => audit.other_events += 1,
        }
    }
}

#[derive(Clone, Copy)]
struct TerminalSize {
    columns: usize,
    screen_lines: usize,
}

impl Dimensions for TerminalSize {
    fn total_lines(&self) -> usize {
        self.screen_lines
    }

    fn screen_lines(&self) -> usize {
        self.screen_lines
    }

    fn columns(&self) -> usize {
        self.columns
    }
}

/// Parser/grid owner. Rendering and every Android capability stay in Kotlin.
pub struct TerminalCore {
    parser: Processor,
    terminal: Term<AuditListener>,
    listener: AuditListener,
    generation: u64,
    size: TerminalSize,
}

impl TerminalCore {
    pub fn new(columns: usize, screen_lines: usize) -> Result<Self, TerminalError> {
        let size = TerminalSize {
            columns,
            screen_lines,
        };
        validate_dimensions(size)?;

        let listener = AuditListener::default();
        let config = Config {
            scrolling_history: MAX_SCROLLBACK_LINES,
            osc52: Osc52::Disabled,
            ..Config::default()
        };

        Ok(Self {
            parser: Processor::new(),
            terminal: Term::new(config, &size, listener.clone()),
            listener,
            generation: 0,
            size,
        })
    }

    pub fn feed(&mut self, bytes: &[u8]) -> Result<u64, TerminalError> {
        if bytes.len() > MAX_INPUT_BYTES {
            return Err(TerminalError::InputTooLarge);
        }

        self.parser.advance(&mut self.terminal, bytes);
        self.generation = self.generation.wrapping_add(1);
        Ok(self.generation)
    }

    pub fn resize(&mut self, columns: usize, screen_lines: usize) -> Result<u64, TerminalError> {
        let size = TerminalSize {
            columns,
            screen_lines,
        };
        validate_dimensions(size)?;
        self.terminal.resize(size);
        self.size = size;
        self.generation = self.generation.wrapping_add(1);
        Ok(self.generation)
    }

    pub fn scroll_display(&mut self, delta: i32) -> Result<u64, TerminalError> {
        if delta.unsigned_abs() as usize > MAX_SCROLLBACK_LINES {
            return Err(TerminalError::ScrollDeltaTooLarge);
        }
        self.terminal.scroll_display(Scroll::Delta(delta));
        self.generation = self.generation.wrapping_add(1);
        Ok(self.generation)
    }

    pub fn event_audit(&self) -> EventAudit {
        self.listener.snapshot()
    }

    pub fn snapshot(&self) -> ScreenSnapshot {
        let content = self.terminal.renderable_content();
        let display_offset = content.display_offset as i32;
        let mut rows = vec![Vec::with_capacity(self.size.columns); self.size.screen_lines];
        let mut stripped_hyperlink_cells = 0;

        for indexed in content.display_iter {
            let viewport_line = indexed.point.line.0 + display_offset;
            let Ok(row_index) = usize::try_from(viewport_line) else {
                continue;
            };
            let Some(row) = rows.get_mut(row_index) else {
                continue;
            };

            if indexed.cell.hyperlink().is_some() {
                stripped_hyperlink_cells += 1;
            }

            let character = if indexed.cell.flags.contains(Flags::HIDDEN)
                || indexed.cell.flags.contains(Flags::WIDE_CHAR_SPACER)
            {
                ' '
            } else {
                indexed.cell.c
            };
            let combining = indexed
                .cell
                .zerowidth()
                .unwrap_or_default()
                .iter()
                .collect();

            row.push(CellSnapshot {
                character,
                combining,
                foreground: color_snapshot(indexed.cell.fg),
                background: color_snapshot(indexed.cell.bg),
                flags: indexed.cell.flags.bits(),
            });
        }

        ScreenSnapshot {
            generation: self.generation,
            columns: self.size.columns,
            screen_lines: self.size.screen_lines,
            rows,
            stripped_hyperlink_cells,
        }
    }
}

fn validate_dimensions(size: TerminalSize) -> Result<(), TerminalError> {
    if size.columns == 0 || size.screen_lines == 0 {
        return Err(TerminalError::EmptyDimensions);
    }
    if size.columns > MAX_COLUMNS || size.screen_lines > MAX_SCREEN_LINES {
        return Err(TerminalError::DimensionsTooLarge);
    }
    Ok(())
}

fn color_snapshot(color: Color) -> CellColor {
    match color {
        Color::Named(named) => CellColor::Named(named as u16),
        Color::Indexed(index) => CellColor::Indexed(index),
        Color::Spec(rgb) => CellColor::Rgb {
            red: rgb.r,
            green: rgb.g,
            blue: rgb.b,
        },
    }
}

fn encode_color(output: &mut Vec<u8>, color: CellColor) {
    match color {
        CellColor::Named(value) => {
            output.push(0);
            output.extend_from_slice(&value.to_le_bytes());
        }
        CellColor::Indexed(value) => {
            output.push(1);
            output.push(value);
            output.push(0);
        }
        CellColor::Rgb { red, green, blue } => {
            output.push(2);
            output.extend_from_slice(&[red, green, blue]);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use alacritty_terminal::vte::ansi::NamedColor;

    fn visible_text(snapshot: &ScreenSnapshot) -> String {
        snapshot.rows[0]
            .iter()
            .flat_map(|cell| std::iter::once(cell.character).chain(cell.combining.chars()))
            .collect::<String>()
            .trim_end()
            .to_owned()
    }

    #[test]
    fn rejects_unbounded_dimensions_and_input() {
        assert!(matches!(
            TerminalCore::new(0, 25),
            Err(TerminalError::EmptyDimensions)
        ));
        assert!(matches!(
            TerminalCore::new(MAX_COLUMNS + 1, 25),
            Err(TerminalError::DimensionsTooLarge)
        ));

        let mut terminal = TerminalCore::new(80, 25).expect("valid dimensions");
        assert_eq!(
            terminal.feed(&vec![0; MAX_INPUT_BYTES + 1]),
            Err(TerminalError::InputTooLarge)
        );
    }

    #[test]
    fn parses_utf8_and_preserves_combining_characters() {
        let mut terminal = TerminalCore::new(80, 25).expect("terminal");
        terminal
            .feed("Cafe\u{301} 🏿\r\n".as_bytes())
            .expect("bounded input");

        assert_eq!(visible_text(&terminal.snapshot()), "Cafe\u{301} 🏿");
    }

    #[test]
    fn preserves_emoji_modifier_for_logical_row_shaping() {
        let mut terminal = TerminalCore::new(80, 25).expect("terminal");
        terminal
            .feed("Emoji wave 👋🏿\r\n".as_bytes())
            .expect("bounded input");

        let snapshot = terminal.snapshot();
        let logical_text = snapshot.rows[0]
            .iter()
            .filter(|cell| cell.flags & Flags::WIDE_CHAR_SPACER.bits() == 0)
            .flat_map(|cell| std::iter::once(cell.character).chain(cell.combining.chars()))
            .collect::<String>()
            .trim_end()
            .to_owned();
        assert_eq!(logical_text, "Emoji wave 👋🏿");
    }

    #[test]
    fn scrolls_bounded_history_and_changes_the_snapshot() {
        let mut terminal = TerminalCore::new(80, 5).expect("terminal");
        let input = (0..20)
            .map(|index| format!("line-{index:02}\r\n"))
            .collect::<String>();
        terminal.feed(input.as_bytes()).expect("bounded input");
        let bottom = terminal.snapshot();

        let generation = terminal.scroll_display(5).expect("bounded scroll");
        let history = terminal.snapshot();
        assert_eq!(history.generation, generation);
        assert_ne!(history.rows, bottom.rows);
        assert_eq!(
            terminal.scroll_display((MAX_SCROLLBACK_LINES + 1) as i32),
            Err(TerminalError::ScrollDeltaTooLarge),
        );
    }

    #[test]
    fn disables_clipboard_and_strips_hyperlink_targets_from_snapshot() {
        let mut terminal = TerminalCore::new(80, 25).expect("terminal");
        terminal
            .feed(b"\x1b]52;c;Y29uYXR1cy1jbGlwYm9hcmQ=\x1b\\")
            .expect("bounded OSC 52");
        terminal
            .feed(b"\x1b]8;;https://example.invalid/\x1b\\open\x1b]8;;\x1b\\")
            .expect("bounded OSC 8");

        let audit = terminal.event_audit();
        assert_eq!(audit.clipboard_reads, 0);
        assert_eq!(audit.clipboard_writes, 0);
        assert_eq!(terminal.snapshot().stripped_hyperlink_cells, 4);
    }

    #[test]
    fn snapshot_generations_change_on_feed_and_resize() {
        let mut terminal = TerminalCore::new(80, 25).expect("terminal");
        assert_eq!(terminal.snapshot().generation, 0);
        assert_eq!(terminal.feed(b"hello").expect("feed"), 1);
        assert_eq!(terminal.resize(100, 30).expect("resize"), 2);

        let snapshot = terminal.snapshot();
        assert_eq!(snapshot.generation, 2);
        assert_eq!((snapshot.columns, snapshot.screen_lines), (100, 30));
    }

    #[test]
    fn named_colors_have_stable_numeric_identity() {
        assert_eq!(
            color_snapshot(Color::Named(NamedColor::Red)),
            CellColor::Named(1)
        );
        assert_eq!(
            color_snapshot(Color::Named(NamedColor::Background)),
            CellColor::Named(257)
        );
    }

    #[test]
    fn binary_snapshot_has_versioned_header_and_no_hyperlink_target() {
        let mut terminal = TerminalCore::new(8, 2).expect("terminal");
        terminal
            .feed(b"\x1b]8;;https://example.invalid/private\x1b\\open\x1b]8;;\x1b\\")
            .expect("feed");

        let encoded = terminal.snapshot().encode_binary();
        assert_eq!(&encoded[..6], b"CTRM\x01\x00");
        assert!(
            !encoded
                .windows(b"example.invalid".len())
                .any(|part| { part == b"example.invalid" })
        );
    }
}

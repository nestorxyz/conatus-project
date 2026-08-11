# ADR 0003: iOS terminal renderer evaluation

**Status:** Deferred by ADR 0004; physical-device acceptance pending
**Date:** 2026-08-09
**Ticket:** C-005
**Application framework:** Native Swift/SwiftUI under ADR 0006

## Context

Conatus needs an iOS terminal that accepts attacker-controlled PTY bytes while
preserving terminal correctness, selection, bounded scrollback, and usable
VoiceOver output. Terminal escape sequences must never open URLs, read or write
the clipboard, post notifications, transfer files, or invoke other privileged
mobile behavior without an explicit product-owned consent path (`S-011`).

ADR 0004 changed the private-alpha target to Android because no physical iPhone
is available for this ticket's acceptance gate. This evaluation is retained for
future iOS work and does not select the Android renderer.

The spike compares three implementation families:

1. SwiftTerm's native UIKit view and Swift parser.
2. xterm.js inside a constrained `WKWebView`.
3. A Conatus-owned native renderer backed by a Rust parser.

The comparison is based on upstream documentation and source at the revisions
listed below. It is not a substitute for the pending physical-device run.

## Provisional decision

Use SwiftTerm behind a Conatus-owned native bridge if the physical-device gate
passes. Pin the reviewed revision, disable implicit and OSC 8 link discovery,
deny OSC 52 clipboard reads and writes, ignore notifications and unhandled
iTerm content, cap scrollback, and do not expose escape-sequence callbacks to
the SwiftUI application. Only raw PTY bytes, explicit user input, dimensions,
selection, and accessibility state cross the renderer boundary.

This decision remains proposed because graphics protocols are processed inside
the renderer rather than a product-owned delegate. The device run must show
bounded memory and no externally visible action for the malicious graphics
cases before this ADR becomes accepted. If that gate fails, use xterm.js core
without link, clipboard, image, or attach add-ons as the fallback spike. Do not
build a new Rust-backed renderer during alpha unless both established options
fail a recorded requirement.

## Comparison

| Criterion | SwiftTerm | xterm.js in `WKWebView` | Rust parser and native renderer |
|---|---|---|---|
| License | MIT | MIT | Depends on parser; Conatus renderer is AGPL-3.0-or-later |
| iOS integration | Native UIKit view; smallest bridge | Requires WebKit lifecycle and a byte bridge | Requires a new parser/rendering/selection/accessibility integration |
| UTF-8 and terminal coverage | Mature Unicode, grapheme, BiDi, ANSI, OSC, and graphics support | Mature ANSI/OSC, Unicode, IME, and broad production use | Parser-dependent; renderer behavior must be built and tested |
| Selection | Built in, but upstream describes selection/accessibility as a relative weakness | Built in | Must be implemented |
| Accessibility | Implements iOS accessibility reading content; physical VoiceOver validation still required | Screen-reader mode, but WebView and SwiftUI traversal need validation | Must be designed and implemented |
| Side-effect boundary | Clipboard, links, and unhandled iTerm content reach delegates and can be denied; graphics decode inside the view | Optional link, clipboard, and image capabilities can be omitted; Web content needs a strict CSP and message allowlist | Fully product-owned, at the cost of the largest attack and maintenance surface |
| Performance risk | Native CoreText/optional Metal; verify device memory and frame behavior | WebKit and JS copies may dominate long scrollback | Unknown until a substantial renderer exists |
| Maintenance risk | One focused Swift dependency | WebKit plus JavaScript packages and a SwiftUI wrapper | Highest; terminal correctness becomes Conatus-owned |

SwiftTerm is preferred provisionally because it has a native iOS view, a
headless engine, explicit terminal options, bounded scrollback, selection, and
an existing accessibility implementation. xterm.js is the fallback because its
core can omit side-effecting add-ons, but it adds a second UI runtime and a more
complex SwiftUI/WebKit isolation boundary. A bespoke renderer is rejected
for alpha because it would make Conatus responsible for terminal parsing,
layout, selection, accessibility, and performance before validating the
product.

## Reviewed upstream evidence

- SwiftTerm revision `1b1235de436fc6974267d793653cd423d96f270b` on
  2026-08-09. Its package is MIT licensed, targets iOS 14 or newer, provides a
  UIKit `TerminalView`, and exposes explicit `TerminalOptions`.
- SwiftTerm's delegate defaults ignore OSC 52 writes and deny OSC 52 reads.
  Link activation is delegated on iOS and can be disabled with
  `linkReporting = .none`.
- SwiftTerm also supports Sixel, Kitty, and iTerm2 graphics. Those paths can
  cause image parsing and platform decoding, so advertised capability flags and
  cache limits are not treated as proof of safe resource behavior.
- xterm.js core is MIT licensed, has no runtime dependencies, supports a screen
  reader mode, and treats clipboard, images, links, and WebSocket attachment as
  separate or embedding-controlled capabilities.
- `libghostty` was considered but not promoted to the device comparison because
  its upstream documentation still says the public library API is not stable.

## Security profile required by the bridge

- Set link reporting to `.none`; terminal output is never directly actionable.
- Return `nil` for clipboard reads and ignore clipboard writes.
- Ignore notification, title, current-directory, bell, and unhandled-content
  callbacks until a separately reviewed product capability exists.
- Never turn OSC, DCS, APC, PM, or CSI payloads into Swift application actions,
  URLs, file paths, notifications, or clipboard operations.
- Use a 10,000-line scrollback cap for this spike and measure its resident-memory
  effect. The production cap remains an open security/privacy decision.
- Disable image capability advertisement. Treat successful parsing of a hidden
  graphics sequence as potentially unsafe until device memory evidence shows
  the path is bounded.
- Feed bytes on the renderer's documented thread and apply bounded chunks from
  the PTY transport; do not expose unbounded `Data` copies across the bridge.
- Keep all fixtures synthetic. Captures and Instruments exports must not contain
  real terminal, repository, path, credential, or provider data.

## Physical-device acceptance gate

Run the manifest in
`apps/mobile/spikes/ios-terminal-renderer/corpus/manifest.tsv` on a supported
physical iPhone in both CoreText and Metal modes where available. Record the
device model, iOS and Xcode versions, renderer revision, build mode, duration,
peak resident memory, hangs/crashes, and every observed callback in the local
report template.

Acceptance requires all of the following:

1. Every corpus case renders or is safely ignored without a crash or hang.
2. No URL, external scheme, clipboard read/write, notification, file transfer,
   focus change, or other mobile action occurs.
3. The 10,000-line trace completes in at most two seconds in a release build,
   remains selectable, and scrolling has no repeated visible stalls.
4. Peak resident memory remains below 150 MiB during the trace and returns to
   within 25 MiB of its pre-trace level after the terminal view is destroyed.
5. VoiceOver reads ASCII, combining characters, emoji, CJK, Arabic, and the
   selected line in a stable order; rotor navigation does not expose raw escape
   bytes as controls.
6. Dynamic Type at the largest accessibility size preserves a usable viewport,
   selection, and escape control access.

The thresholds are spike gates, not final product budgets. Failure records the
case and triggers the xterm.js fallback run; it does not justify weakening
`S-011` or removing the malicious input.

## Evidence handling

The repository tracks only the synthetic corpus, harness instructions, blank
report template, and the final sanitized result. Raw device logs and Instruments
captures stay outside Git. `make -C apps/mobile spike` validates the tracked
corpus and report schema without requiring Xcode.

## Consequences

- C-042 may integrate only the renderer and revision accepted by this ADR's
  physical-device gate.
- C-043 owns explicit paste consent and user-initiated link behavior; renderer
  escape sequences cannot bypass those controls.
- Terminal parser fuzzing remains required before alpha security review.
- C-005 remains incomplete and C-042 stays blocked until this ADR is accepted
  with a sanitized physical-device report.

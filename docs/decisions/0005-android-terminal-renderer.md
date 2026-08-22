# ADR 0005: Android terminal renderer evaluation

**Status:** Accepted
**Date:** 2026-08-10
**Accepted:** 2026-08-23
**Ticket:** C-008

## Context

Conatus needs an Android terminal that accepts attacker-controlled PTY bytes
while preserving UTF-8, selection, bounded scrollback, lifecycle recovery, and
usable TalkBack output. Terminal escape sequences must not open activities,
read or write the clipboard, post notifications, resolve content providers, or
invoke other privileged Android behavior (`S-011`).

The spike compares these implementation families:

1. A Conatus-owned Kotlin view backed by the Rust `alacritty_terminal` parser.
2. xterm.js core in a locally loaded, network-disabled Android `WebView`.
3. The Termux `terminal-emulator` and `terminal-view` libraries.

The comparison uses upstream documentation and source reviewed on 2026-08-10.
It is not a substitute for the required physical-device run.

## Decision

Build a Conatus-owned native Kotlin terminal view backed by the Rust
`alacritty_terminal` parser. This deliberately optimizes for the long-term
Android experience and a product-owned security boundary rather than the
shortest alpha implementation. Rust owns byte parsing and terminal-grid state;
Kotlin owns text layout, drawing, touch selection, IME integration, TalkBack
semantics, font scaling, and Android lifecycle behavior. A narrow JNI boundary
passes bounded byte chunks into Rust and immutable, generation-tagged screen
snapshots or dirty-row updates back to Kotlin.

The native prototype passed the release corpus and 10,000-line trace on a
physical Android phone. xterm.js in a locked-down local `WebView` remains the
fallback if later production integration cannot preserve terminal correctness,
TalkBack, lifecycle, selection, performance, or the side-effect boundary.
Termux remains rejected on licensing-boundary grounds.

The native choice does not authorize a reduced emulator. Before C-042, the
prototype must demonstrate the terminal behavior needed for Bash, tmux, and
full-screen CLI agents, and the implementation backlog must split layout,
selection, IME, accessibility, and parser-hardening into reviewable work.

## Comparison

| Criterion | xterm.js in local `WebView` | Termux libraries | Rust parser and Kotlin view |
|---|---|---|---|
| License | MIT | Termux application code is GPLv3 with file-specific exceptions; not a clean permissive dependency without a file-level legal inventory | `alacritty_terminal` is Apache-2.0/MIT; Conatus view is AGPL-3.0-or-later |
| Maintenance | Active, widely embedded terminal core | Active Android terminal, but library distribution and license boundaries require extra review | Parser is active; Android rendering and integration become Conatus-owned |
| UTF-8 and terminal coverage | Mature ANSI/OSC, CJK, emoji, IME, resize, and selection | Mature Android terminal behavior | Mature parser baseline; grapheme layout, rendering, selection, and IME still must be built |
| Accessibility | Screen-reader mode exists; TalkBack plus WebView/native traversal require device proof | No sufficient upstream evidence to accept TalkBack behavior without a prototype | Semantics can be product-owned but must be designed and implemented |
| Side-effect boundary | Dangerous features are optional add-ons or embedding APIs; `WebView` itself adds a large platform boundary | Terminal callbacks and app-derived behavior require a source audit; GPL boundary blocks selection first | Smallest capability boundary after JNI, but native parser and renderer memory safety remain in scope |
| Performance risk | JavaScript/DOM and bridge copies may dominate long scrollback | Native Android rendering, subject to device measurement | Potentially efficient; substantial unmeasured rendering work |
| Native Android integration | A Compose-hosted `WebView` with a narrow byte/message bridge | Native view adaptation of app-oriented APIs | JNI plus a Compose-hosted custom view, accessibility tree, selection, and IME |
| Delivery risk | Moderate | License and integration risk | Highest |

The Rust-backed option is preferred because it offers the highest long-term UX
ceiling and the clearest product-owned side-effect boundary. It also has the
highest delivery risk: Conatus becomes responsible for Android rendering,
grapheme layout, selection, IME, accessibility, JNI safety, and their ongoing
compatibility. This is an explicit product tradeoff, not an inference that a
custom renderer is cheaper or more mature.

xterm.js is the fallback because its core is permissively licensed, actively
maintained, production-used, selectable, and accessibility-aware while
side-effecting capabilities are optional. Termux is rejected for this spike
because the repository is primarily GPLv3 and its exceptions must not be
generalized to terminal modules without a file-level provenance review.

The archived Jackpal Android Terminal Emulator and young Android terminal forks
were reviewed but not promoted to the device comparison: maintenance and modern
accessibility evidence are insufficient for a security-critical new embedding.

## Reviewed upstream evidence

- xterm.js core is MIT licensed, has no runtime dependencies, supports Unicode,
  IME, selection, resize, and an opt-in screen-reader mode. Clipboard, links,
  images, WebSocket attachment, fonts, and WebGL are separate add-ons.
- Termux documents `terminal-view` and `terminal-emulator` as importable
  libraries. Its repository license states that code not covered by explicit
  exceptions remains GPLv3, so permissive reuse cannot be assumed at module
  level.
- `alacritty_terminal` 0.26.0 is the pinned parser/state crate from Alacritty,
  whose source is dual Apache-2.0/MIT. Its exact transitive resolution and
  registry checksums are recorded in the spike `Cargo.lock`. It does not supply
  an Android view, TalkBack semantics, selection UI, or Android application
  integration.
- `jni` 0.21.1 is pinned for the prototype's versioned, bounded JNI exports;
  it does not grant parser events a generic Java callback surface.
- Jackpal's Android Terminal Emulator is archived and its last documented
  release predates current Android platform and accessibility expectations.

Dependency releases are exact-pinned and checksummed in `Cargo.lock`. A moving
branch or an unreviewed CDN artifact is forbidden.

## Required security and ownership profile

- Rust owns terminal parsing, mode state, grid mutation, scrollback bounds, and
  parser replies. Kotlin must not independently reinterpret escape sequences.
- Kotlin owns Android drawing, font metrics, touch selection, IME, TalkBack,
  focus, and lifecycle. No parser event maps directly to an Android intent,
  URI, clipboard, notification, permission, file, or content-provider API.
- JNI exposes a closed, versioned interface for bounded input, resize, snapshot,
  dirty rows, selection coordinates, reset, and destruction. Validate lengths,
  dimensions, generations, and enum discriminants on both sides.
- Screen snapshots are immutable and generation-tagged. Kotlin discards stale
  generations after resize, recreation, or destruction rather than combining
  incompatible state.
- Render with Android text and canvas APIs first. GPU-specific acceleration is
  allowed only after the correctness and accessibility path passes without it.
- Provide TalkBack through product-owned virtual accessibility nodes derived
  from visible logical lines and selection, never raw escape bytes or JNI
  object identity.
- Ignore OSC title, current-directory, hyperlink, clipboard, notification,
  shell-integration, and graphics behavior. Parser replies are captured in
  memory for the test and never sent to a network transport by the harness.
- Cap scrollback at exactly 10,000 lines for the spike and measure the resident
  memory effect. The production cap remains a separate security/privacy choice.
- Feed bounded byte chunks through the renderer's documented thread. Do not log
  payloads, rendered text, selections, bridge messages, or accessibility text.
- Keep fixtures synthetic. Raw profiler, logcat, screenshot, and accessibility
  captures stay outside Git.

If the xterm.js fallback is invoked, it must load only bundled assets, omit all
side-effecting add-ons, deny navigation and resource requests, request no
network permission, and avoid `addJavascriptInterface`.

## Physical-device acceptance gate

Run `apps/mobile/spikes/android-terminal-renderer/corpus/manifest.tsv` in the
disposable release harness on a supported physical Android phone. Record the
device, Android/API, renderer revision, Android Gradle Plugin, Gradle, JDK,
duration, peak resident memory, lifecycle, selection, largest font scale, and
TalkBack results in a sanitized local report.

Acceptance requires all of the following:

1. Every corpus case renders or is safely ignored without a crash, ANR, or hang.
2. No URL or activity launch, external scheme, clipboard access, notification,
   download, file/content-provider access, permission prompt, or other Android
   side effect occurs.
3. The 10,000-line trace completes in at most two seconds in a release build,
   remains selectable, and scrolling has no repeated visible stalls.
4. Peak proportional-set memory remains below 180 MiB during the trace and
   returns to within 30 MiB of its pre-trace value after the terminal is
   destroyed and garbage collection has had a measurement interval.
5. Background/foreground, activity recreation, and rotation neither repeat a
   bridge effect nor fabricate unavailable terminal history.
6. TalkBack reads ASCII, combining characters, emoji, CJK, Arabic, and the
   selected line in stable order without exposing escape bytes or duplicate
   accessibility nodes.
7. The largest Android font scale preserves a usable viewport, selection, and
   access to terminal controls.

The thresholds are spike gates, not final product budgets. A failure records
the case and triggers the locked-down xterm.js fallback; it cannot weaken
`S-011` or remove malicious input.

## Evidence handling

The repository tracks the synthetic corpus, harness contract, blank report
template, validator, and final sanitized result only. A pending report is not
acceptance evidence. Raw device and profiler artifacts remain outside Git.

## Physical-device result

The sanitized [C-008 report](../../apps/mobile/spikes/android-terminal-renderer/report.tsv)
records the accepted physical-device run against harness commit
`8e4f9644712e6f819619f754e198c8bbf7ca888b`. The API-28 Motorola Moto G6 Plus
completed all 21 cases in 505 ms without a sensitive permission prompt or
observed external side effect. The highest observed proportional-set memory was
113.1 MiB, and the measured post-destroy delta was 9.7 MiB. Scrollback,
selection, lifecycle recreation, rotation, largest-font-scale usability, and
TalkBack's per-line traversal and selection passed.

The staged run intentionally found and corrected missing live scrollback, an
accessibility-disabled selection exception, cell-by-cell Unicode shaping, and
one-block TalkBack exposure before acceptance. Those failed precursor builds
are retained in the device handoff and are not represented as passing evidence.

## Consequences

- C-042 may integrate only the renderer and revision accepted after this ADR's
  physical-device gate. The next implementation step is the disposable native
  Rust/Kotlin prototype; production integration remains out of scope for C-008.
- C-043 owns explicit paste consent and user-initiated link behavior; terminal
  escape sequences cannot bypass those controls.
- Terminal parser fuzzing remains required before alpha security review.
- C-008 is complete. C-042 may use this accepted renderer decision only after
  its other dependency, C-041, is complete and must still satisfy its own
  production integration and security acceptance criteria.

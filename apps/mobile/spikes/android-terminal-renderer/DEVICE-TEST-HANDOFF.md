# C-008 physical Android test handoff

**Status:** Corrected scrolling build awaits physical-device rerun; complete
device evidence is still required before C-008 or ADR 0005 can be accepted.

The host corpus, Rust tests, formatting, Clippy, repository bootstrap, Android
release compilation, release lint, and APK assembly passed on 2026-08-10. The
Android project currently has no JVM unit-test sources; Gradle reports
`testReleaseUnitTest NO-SOURCE`. These results do not substitute for the device
gate.

## First device attempt

On 2026-08-22, the operator ran the release harness on the API-28 Moto G6 Plus.
All 21 cases completed in 640 ms without an immediate crash, hang, permission
prompt, or observed external side effect. A later targeted memory reading was
64,432 KiB total PSS. When the operator attempted to scroll, the visible task
closed but the package process remained alive.

Code review found that the harness had destroyed every native terminal after
capturing only the final 25-row snapshot, so no live scrollback path existed.
The run therefore fails the scroll/selection gate and is not C-008 acceptance
evidence. The corrected harness retains exactly one bounded long-trace handle,
adds a bounded JNI display-offset operation, refreshes immutable snapshots
after touch scrolling, and closes the handle on activity destruction. It must
be rerun from the beginning.

The corrected scrolling build at commit
`804bb0816d2ca6465a4d58523f248f94a0584437` then completed all 21 cases in
614 ms and rendered live scrollback. Tapping a row crashed the process on the
API-28 device. A filtered application-only trace identified
`IllegalStateException: Accessibility off` at the view's unchecked
accessibility-event call. This is a failed selection attempt, not acceptance
evidence. The subsequent correction uses the platform's guarded announcement
path only while accessibility is enabled; selection without TalkBack must be
rerun before enabling TalkBack for its separate ceremony.

The first visual accessibility sample then exposed the emoji skin-tone modifier
as a separate square and disconnected Arabic shaping. This fails Unicode
rendering and is not TalkBack evidence. The cell-by-cell Canvas renderer was
replaced with logical-row shaping after removing only parser-marked wide-cell
spacers; the corrected sample must be visually rerun before TalkBack is enabled.

The corrected visual sample passed, but TalkBack exposed the terminal as one
large block. This fails the required per-line virtual-node model and is not
accessibility acceptance evidence. The next build exposes one bounded virtual
text node per non-empty visible logical row, maintains stable row order,
supports accessibility focus, and maps virtual-node click to sanitized line
selection. It awaits a TalkBack-only rerun.

## Build and transfer

Build the current checkout on the VPS using the pinned repository-local
toolchain as documented in [README.md](README.md). Confirm that the resulting
APK is:

```text
android-harness/app/build/outputs/apk/release/app-release.apk
```

From the Mac, transfer it only through the private SSH alias and install it on
an ARM64 Android phone with USB debugging already approved:

```sh
scp contabo-vps:/srv/projects/canotus-project/apps/mobile/spikes/android-terminal-renderer/android-harness/app/build/outputs/apk/release/app-release.apk .
adb devices -l
adb install -r app-release.apk
```

Do not distribute this disposable debug-signed APK. The harness requests no
Android permissions and must remain disconnected from PTYs, SSH endpoints, the
control plane, and production application state.

## Test procedure

1. Copy `report.template.tsv` to the Git-ignored local file `report.tsv`.
2. Record the device model, Android version and API level, TalkBack version,
   operator, run date, renderer revision and checksum, and every pinned
   toolchain version before testing.
3. Install a release build, open **C-008 native terminal spike**, and select
   **Run corpus**. Confirm every tracked case completes without a crash, ANR,
   or hang. Record the displayed case count and duration.
4. Confirm that the corpus causes no activity or URL launch, external scheme,
   clipboard read or write, notification, download, network write, window-title
   change, resize request, image export, bridge message, permission prompt,
   file access, or content-provider access.
5. Run the 10,000-line trace in at most two seconds. Exercise scrolling and
   select a visible line; **Inspect selection** must report the selected line.
6. Measure peak proportional-set memory with Android Studio Profiler or
   `adb shell dumpsys meminfo dev.conatus.terminal.spike`. It must remain below
   180 MiB. Destroy the terminal/activity, allow a measurement interval after
   garbage collection, and confirm memory returns to within 30 MiB of the
   pre-trace value.
7. Exercise background/foreground, rotation, and activity recreation. Confirm
   that no bridge effect repeats and no unavailable history is fabricated.
8. At the largest Android font scale, confirm the viewport, selection, and
   terminal controls remain usable.
9. With TalkBack enabled, verify stable reading order for ASCII, combining
   characters, emoji, CJK, Arabic, and a selected line using **Show
   accessibility sample**. TalkBack may speak the rendered words `ANSI red
   without escape bytes`, but must not announce raw escape/control bytes or
   duplicate the sample.
10. Keep profiler output, logcat, screenshots, and accessibility captures
    outside Git. Put only aggregate, sanitized results in `report.tsv`.

## Closeout

From the repository root, validate the completed report:

```sh
PATH="$HOME/.cargo/bin:$PATH" make -C apps/mobile android-spike
```

If every gate in ADR 0005 passes, commit the sanitized `report.tsv`, change ADR
0005 from Proposed to Accepted, and mark C-008 complete in the implementation
backlog. If any gate fails, record the failing case, keep C-008 incomplete, and
evaluate the locked-down xterm.js fallback. Do not weaken the thresholds or the
terminal side-effect invariant.

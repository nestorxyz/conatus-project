# C-008 Android terminal-renderer spike

This directory contains the synthetic inputs, disposable harness, and sanitized
physical-device evidence for C-008. It contains no production mobile code or
real terminal output. The physical-device gate passed on 2026-08-23; see
[report.tsv](report.tsv) for the accepted aggregate result and
[DEVICE-TEST-HANDOFF.md](DEVICE-TEST-HANDOFF.md) for the remediation history.

`native-core` is the platform-neutral Rust parser/grid prototype. It is built
as both an `rlib` for host corpus tests and a `cdylib` for the Android JNI
wrapper. `android-harness` is the disposable no-sensitive-permission Kotlin/Compose
application and custom terminal `View`; it is not production mobile code.

Run its locked tests directly with:

```sh
cargo test --locked \
  --manifest-path apps/mobile/spikes/android-terminal-renderer/native-core/Cargo.toml
```

The core parses every tracked corpus case, enforces input and dimension bounds,
disables OSC 52, strips hyperlink targets from screen snapshots, records only
aggregate parser-event counters, and exports opaque-handle JNI functions. Its
binary snapshot starts with the versioned `CTRM` header; Kotlin must reject
unknown versions and stale generations. After the corpus, the harness retains
exactly one bounded native terminal handle for scrollback interaction; gestures
request bounded display-offset changes and fresh immutable snapshots. Activity
destruction closes the retained handle.

## Validate tracked evidence

From the repository root:

```sh
make -C apps/mobile android-spike
```

The check validates the corpus, candidate record, completed report schema, and
the numeric and pass/fail gates from ADR 0005. It does not compile an Android
application or reproduce the physical-phone run.

## Device harness contract

1. Create a disposable Android application with no network permission and a
   single activity containing a native Kotlin terminal view backed by a pinned
   `alacritty_terminal` revision. Record the revision, license, checksum, Rust,
   Cargo, NDK, Android Gradle Plugin, Gradle, and JDK versions before running it.
2. Expose only bounded input, resize, immutable generation-tagged screen data,
   dirty rows, selection coordinates, reset, and destruction across JNI.
   Validate lengths, dimensions, generations, and enums on both sides.
3. Render with Android text/canvas APIs. Implement touch selection, IME input,
   maximum font scale, and virtual TalkBack nodes in Kotlin. The view must not
   expose an intent, URI, clipboard, notification, permission, file, or content
   API to parser events.
4. Decode each `hex_payload` from `corpus/manifest.tsv` and feed it in bounded
   chunks to a fresh 80-by-25 terminal. Record bounded parser replies and
   counters for any forbidden platform-call attempts without recording payload
   content.
5. For `long-scrollback`, generate exactly 10,000 synthetic lines from the
   manifest instruction. Do not materialize or log the complete trace.
6. Exercise selection without writing the clipboard, TalkBack, maximum font
   scale, rotation, background/foreground, activity recreation, and terminal
   view destruction.
7. Measure a release build with Android Studio's profiler or `dumpsys meminfo`.
   Keep raw output and captures outside Git; transfer only sanitized aggregate
   measurements into `report.tsv`.
8. Complete every report field and run the validator. ADR 0005 may be accepted
   and C-008 completed only if every gate passes.

The harness must request no network, notification, storage, media, contacts,
location, accessibility-service, overlay, or package-install permission. It
must not connect to a PTY, SSH endpoint, control plane, or production app
runtime.

## Build on the VPS and install from a Mac

Install the pinned, repository-local toolchain once and build the disposable
ARM64 APK from the repository root:

```sh
./scripts/setup-android-spike-toolchain.sh
env JAVA_HOME="$PWD/.cache/android-toolchain/jdk-17.0.19+10" \
  ANDROID_HOME="$PWD/.cache/android-toolchain/sdk" \
  ANDROID_SDK_ROOT="$PWD/.cache/android-toolchain/sdk" \
  ANDROID_NDK_HOME="$PWD/.cache/android-toolchain/sdk/ndk/27.0.12077973" \
  PATH="$PWD/.cache/android-toolchain/jdk-17.0.19+10/bin:$HOME/.cargo/bin:$PATH" \
  apps/mobile/spikes/android-terminal-renderer/android-harness/gradlew \
  -p apps/mobile/spikes/android-terminal-renderer/android-harness assembleRelease
```

The VPS does not need a direct connection to the phone. On the Mac, with the
Android device connected over USB and USB debugging approved, transfer and
install the APK:

```sh
scp contabo-vps:/srv/projects/canotus-project/apps/mobile/spikes/android-terminal-renderer/android-harness/app/build/outputs/apk/release/app-release.apk .
adb devices -l
adb install -r app-release.apk
```

This harness contains only `arm64-v8a`, so the test device must support ARM64.
The release APK uses a disposable debug signing key and is for internal C-008
device testing only.

## Corpus format

`manifest.tsv` is tab-separated with these fields:

- `id`: stable lowercase case identifier
- `category`: `text`, `control`, `side-effect`, `resource`, or `performance`
- `encoding`: `hex` or `generated`
- `payload`: hexadecimal bytes, or the fixed generation instruction
- `expected`: `render`, `ignore`, or `bounded`
- `forbidden_effect`: external behavior that must not occur, or `none`

The payloads remain inert text until the disposable device harness explicitly
decodes the hexadecimal field.

#!/bin/sh
# SPDX-FileCopyrightText: 2026 Conatus contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

base=apps/mobile/spikes/android-terminal-renderer
manifest=$base/corpus/manifest.tsv
candidates=$base/candidates.tsv
template=$base/report.template.tsv
native_manifest=$base/native-core/Cargo.toml
native_lock=$base/native-core/Cargo.lock
android_manifest=$base/android-harness/app/src/main/AndroidManifest.xml
android_build=$base/android-harness/app/build.gradle.kts
android_lock=$base/android-harness/app/gradle.lockfile
gradle_wrapper=$base/android-harness/gradle/wrapper/gradle-wrapper.properties
terminal_view=$base/android-harness/app/src/main/java/dev/conatus/terminal/TerminalView.kt

fail() {
  printf 'Android terminal spike: %s\n' "$1" >&2
  exit 1
}

for file in "$manifest" "$candidates" "$template" "$native_manifest" "$native_lock" \
  "$android_manifest" "$android_build" "$android_lock" "$gradle_wrapper" \
  "$terminal_view"; do
  test -f "$file" || fail "$file is missing"
done

grep -F 'alacritty_terminal = "=0.26.0"' "$native_manifest" >/dev/null ||
  fail 'native core must pin the reviewed alacritty_terminal 0.26.0 release'
grep -F 'jni = "=0.21.1"' "$native_manifest" >/dev/null ||
  fail 'native core must pin the reviewed jni 0.21.1 release'

grep -q '<uses-permission' "$android_manifest" &&
  fail 'disposable Android harness must not request permissions'
grep -F 'compileSdk = 36' "$android_build" >/dev/null ||
  fail 'Android harness must pin compile SDK 36'
grep -F 'ndkVersion = "27.0.12077973"' "$android_build" >/dev/null ||
  fail 'Android harness must pin NDK 27.0.12077973'
grep -F 'distributionUrl=https\://services.gradle.org/distributions/gradle-8.13-bin.zip' "$gradle_wrapper" >/dev/null ||
  fail 'Android harness must pin Gradle 8.13'
grep -F 'distributionSha256Sum=20f1b1176f96aab99a3a6ac0930c4a6d8e5c329fbb1a56037e23d0e3e8f69712' "$gradle_wrapper" >/dev/null ||
  fail 'Gradle wrapper distribution checksum is missing or incorrect'
grep -F 'androidx.activity:activity-compose:1.13.0=' "$android_lock" >/dev/null ||
  fail 'Android harness dependency lock is incomplete'
grep -F 'class TerminalView' "$terminal_view" >/dev/null ||
  fail 'native Kotlin terminal view is missing'

awk -F '\t' '
  NR == 1 {
    if ($0 != "id\tcategory\tencoding\tpayload\texpected\tforbidden_effect") exit 10
    next
  }
  NF != 6 { exit 11 }
  $1 !~ /^[a-z0-9]+(-[a-z0-9]+)*$/ { exit 12 }
  seen[$1]++ { exit 13 }
  $2 !~ /^(text|control|side-effect|resource|performance)$/ { exit 14 }
  $3 !~ /^(hex|generated)$/ { exit 15 }
  $5 !~ /^(render|ignore|bounded)$/ { exit 16 }
  $3 == "hex" && ($4 !~ /^[0-9a-f]+$/ || length($4) % 2 != 0) { exit 17 }
  $3 == "generated" && $4 != "10000-lines:line-%05d-alpha-beta-gamma-crlf" { exit 18 }
  END { if (NR < 20) exit 19 }
' "$manifest" || fail 'corpus manifest has invalid schema or data'

required_effects='activity-launch external-scheme clipboard-write clipboard-read notification window-title content-provider download image-export bridge-message activity-resize network-write'
for effect in $required_effects; do
  awk -F '\t' -v expected="$effect" 'NR > 1 && $6 == expected { found = 1 } END { exit !found }' "$manifest" ||
    fail "corpus does not cover $effect"
done

awk -F '\t' '
  NR == 1 {
    if ($0 != "candidate\tfamily\tlicense\tstatus\treason") exit 20
    next
  }
  NF != 5 { exit 21 }
  seen[$1]++ { exit 22 }
  $4 !~ /^(device-candidate|fallback|rejected-license|rejected-maintenance)$/ { exit 23 }
  { status[$1] = $4 }
  END {
    if (NR < 5) exit 24
    if (!seen["xterm-js-webview"]) exit 25
    if (!seen["termux-terminal-view"]) exit 26
    if (!seen["alacritty-terminal-kotlin-view"]) exit 27
    if (status["alacritty-terminal-kotlin-view"] != "device-candidate") exit 28
    if (status["xterm-js-webview"] != "fallback") exit 29
  }
' "$candidates" || fail 'candidate record has invalid schema or missing families'

awk -F '\t' '
  NR == 1 { if ($0 != "field\tvalue") exit 30; next }
  NF != 2 { exit 31 }
  seen[$1]++ { exit 32 }
  END {
    required["status"] = 1
    required["device_model"] = 1
    required["android_version"] = 1
    required["android_api_level"] = 1
    required["renderer_revision"] = 1
    required["android_gradle_plugin_version"] = 1
    required["gradle_version"] = 1
    required["jdk_version"] = 1
    required["rust_version"] = 1
    required["cargo_version"] = 1
    required["android_ndk_version"] = 1
    required["trace_duration_ms"] = 1
    required["peak_pss_mib"] = 1
    required["lifecycle_result"] = 1
    required["selection_result"] = 1
    required["largest_font_scale_result"] = 1
    required["talkback_result"] = 1
    required["external_side_effect"] = 1
    required["operator"] = 1
    required["run_date"] = 1
    for (field in required) if (!seen[field]) exit 33
  }
' "$template" || fail 'report template has invalid schema or missing fields'

if test -f "$base/report.tsv"; then
  cmp -s "$template" "$base/report.tsv" &&
    fail 'report.tsv is still the blank template and is not device evidence'
  awk -F '\t' '
    NR == 1 {
      if ($0 != "field\tvalue") exit 40
      next
    }
    NF != 2 || $2 == "" || $2 == "pending" { exit 40 }
    seen[$1]++ { exit 41 }
    $1 == "status" && $2 != "pass" { exit 42 }
    $1 == "build_mode" && $2 != "release" { exit 43 }
    $1 == "android_api_level" && $2 !~ /^[0-9]+$/ { exit 44 }
    $1 == "trace_duration_ms" {
      if ($2 !~ /^[0-9]+$/ || $2 + 0 > 2000) exit 45
    }
    $1 == "peak_pss_mib" {
      if ($2 !~ /^[0-9]+([.][0-9]+)?$/ || $2 + 0 >= 180) exit 46
    }
    $1 == "pss_delta_after_destroy_mib" {
      if ($2 !~ /^[0-9]+([.][0-9]+)?$/ || $2 + 0 > 30) exit 47
    }
    $1 ~ /^(crash_anr_or_hang|external_side_effect|lifecycle_result|selection_result|largest_font_scale_result|talkback_result)$/ &&
      $2 !~ /^pass([:;]|$)/ { exit 48 }
    END {
      required["status"] = 1
      required["build_mode"] = 1
      required["android_api_level"] = 1
      required["trace_duration_ms"] = 1
      required["peak_pss_mib"] = 1
      required["pss_delta_after_destroy_mib"] = 1
      required["crash_anr_or_hang"] = 1
      required["external_side_effect"] = 1
      required["lifecycle_result"] = 1
      required["selection_result"] = 1
      required["largest_font_scale_result"] = 1
      required["talkback_result"] = 1
      for (field in required) if (!seen[field]) exit 49
    }
  ' "$base/report.tsv" || fail 'report.tsv is incomplete or invalid'
  printf 'Android terminal spike: sanitized physical-device evidence passes enforced gates\n'
  exit 0
fi

printf 'Android terminal spike: tracked evidence valid (physical-device run still required)\n'

#!/bin/sh
# SPDX-FileCopyrightText: 2026 Conatus contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cache=$repository/.cache/android-toolchain
downloads=$cache/downloads
sdk=$cache/sdk

jdk_archive=$downloads/OpenJDK17U-jdk_x64_linux_hotspot_17.0.19_10.tar.gz
jdk_sha=d8afc263758141a66e0e3aafc321e783f7016696f4eaea067d340a269037d331
jdk_url=https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.19%2B10/OpenJDK17U-jdk_x64_linux_hotspot_17.0.19_10.tar.gz
jdk_home=$cache/jdk-17.0.19+10

gradle_archive=$downloads/gradle-8.13-bin.zip
gradle_sha=20f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78
gradle_url=https://services.gradle.org/distributions/gradle-8.13-bin.zip
gradle_home=$cache/gradle-8.13

tools_archive=$downloads/commandlinetools-linux-15859902_latest.zip
tools_sha=4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583
tools_url=https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip

mkdir -p "$downloads" "$sdk/cmdline-tools"

download() {
  url=$1
  destination=$2
  expected=$3
  if test ! -f "$destination"; then
    curl -fL --retry 3 --output "$destination.part" "$url"
    mv "$destination.part" "$destination"
  fi
  printf '%s  %s\n' "$expected" "$destination" | sha256sum -c - >/dev/null
}

download "$jdk_url" "$jdk_archive" "$jdk_sha"
if test ! -x "$jdk_home/bin/java"; then
  tar -xzf "$jdk_archive" -C "$cache"
fi

download "$gradle_url" "$gradle_archive" "$gradle_sha"
if test ! -x "$gradle_home/bin/gradle"; then
  busybox unzip -q "$gradle_archive" -d "$cache"
fi

download "$tools_url" "$tools_archive" "$tools_sha"
if test ! -x "$sdk/cmdline-tools/latest/bin/sdkmanager"; then
  staging=$cache/command-line-tools-staging
  mkdir -p "$staging"
  busybox unzip -q "$tools_archive" -d "$staging"
  mv "$staging/cmdline-tools" "$sdk/cmdline-tools/latest"
  rmdir "$staging"
fi

export JAVA_HOME=$jdk_home
export ANDROID_HOME=$sdk
export ANDROID_SDK_ROOT=$sdk
export PATH=$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:/home/nestor/.cargo/bin:$PATH

# The founder explicitly approved accepting these terms on 2026-08-10 for the
# isolated C-008 toolchain.
yes | sdkmanager --licenses >/dev/null
sdkmanager \
  'platform-tools' \
  'platforms;android-36' \
  'build-tools;35.0.0' \
  'ndk;27.0.12077973'

rustup target add aarch64-linux-android

printf 'JAVA_HOME=%s\n' "$JAVA_HOME"
printf 'ANDROID_HOME=%s\n' "$ANDROID_HOME"
printf 'GRADLE_HOME=%s\n' "$gradle_home"

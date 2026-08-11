#!/bin/sh
# SPDX-FileCopyrightText: 2026 Conatus contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

abi=${1:-arm64-v8a}
case "$abi" in
  arm64-v8a)
    rust_target=aarch64-linux-android
    clang_prefix=aarch64-linux-android26
    ;;
  *)
    printf 'unsupported Android ABI: %s\n' "$abi" >&2
    exit 2
    ;;
esac

: "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME must name the pinned Android NDK directory}"

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
toolchain=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin
linker=$toolchain/$clang_prefix-clang
test -x "$linker" || {
  printf 'Android linker not found: %s\n' "$linker" >&2
  exit 2
}

export PATH=/home/nestor/.cargo/bin:$PATH
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=$linker

manifest=$repository/apps/mobile/spikes/android-terminal-renderer/native-core/Cargo.toml
cargo build --locked --release --target "$rust_target" --manifest-path "$manifest"

destination=$repository/.cache/android-terminal-jni/$abi
mkdir -p "$destination"
cp "$repository/apps/mobile/spikes/android-terminal-renderer/native-core/target/$rust_target/release/libconatus_android_terminal_spike.so" "$destination/"

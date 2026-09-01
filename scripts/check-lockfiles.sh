#!/bin/sh
# SPDX-FileCopyrightText: 2026 Conatus contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

fail() {
  printf 'lock check: %s\n' "$1" >&2
  exit 1
}

find . -path './.git' -prune -o -path './.cache' -prune -o \
  -path './node_modules' -prune -o -path '*/.build' -prune -o \
  -path './build' -prune -o -path './dist' -prune -o \
  -path './tests/fixtures' -prune -o \
  -name Cargo.toml -print | while IFS= read -r manifest; do
  directory=${manifest%/*}
  test -f "$directory/Cargo.lock" || fail "$manifest has no Cargo.lock"
done

find . -path './.git' -prune -o -path './.cache' -prune -o \
  -path './node_modules' -prune -o -path '*/.build' -prune -o \
  -path './build' -prune -o -path './dist' -prune -o \
  -path './tests/fixtures' -prune -o \
  -name package.json -print | while IFS= read -r manifest; do
  directory=${manifest%/*}
  case "$manifest" in
    ./package.json|./services/core/package.json|./packages/contracts/package.json)
      test -f pnpm-workspace.yaml || fail 'pnpm workspace definition is missing'
      test -f pnpm-lock.yaml || fail 'pnpm workspace has no lockfile'
      continue
      ;;
  esac
  test -f "$directory/package-lock.json" || test -f "$directory/yarn.lock" ||
    test -f "$directory/pnpm-lock.yaml" || fail "$manifest has no supported lockfile"
done

if test -d .github/workflows; then
  workflow_actions=$(grep -RhE '^[[:space:]]*-[[:space:]]+uses:' .github/workflows || true)
  if test -n "$workflow_actions" &&
    printf '%s\n' "$workflow_actions" | grep -Ev 'uses:[[:space:]]+[^[:space:]@]+@[0-9a-f]{40}([[:space:]]|$)' >/dev/null 2>&1; then
    fail 'GitHub Actions must be pinned to a full commit SHA'
  fi
fi

printf 'lock check: manifests are locked\n'

#!/bin/sh
# SPDX-FileCopyrightText: 2026 Conatus contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

components='apps/mobile agents/machine services/control-plane packages/protocol packages/test-vectors'

fail() {
  printf 'bootstrap: %s\n' "$1" >&2
  exit 1
}

for component in $components; do
  test -f "$component/README.md" || fail "$component has no README"
  test -f "$component/OWNERS" || fail "$component has no owner declaration"
  test -f "$component/Makefile" || fail "$component has no build entry point"
  grep -q '^Owner:' "$component/OWNERS" || fail "$component has an invalid owner declaration"
  grep -q '^## Dependency boundary$' "$component/README.md" ||
    fail "$component has no dependency boundary"
  make --no-print-directory -C "$component" verify
done

./scripts/check-licensing.sh
printf 'bootstrap: verified %s components\n' 5

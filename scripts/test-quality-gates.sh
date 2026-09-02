#!/bin/sh
# SPDX-FileCopyrightText: 2026 Conatus contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

expect_failure() {
  name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'quality gate test: %s unexpectedly passed\n' "$name" >&2
    exit 1
  fi
  printf 'quality gate test: %s rejected as expected\n' "$name"
}

expect_failure malformed-format ./scripts/check-format.sh tests/fixtures/bad-format.md
expect_failure test-failure sh tests/fixtures/failing-test.sh
expect_failure fake-secret ./scripts/check-secrets.sh tests/fixtures/secret-case
expect_failure prohibited-license ./scripts/check-dependency-licenses.sh tests/fixtures/prohibited-licenses.tsv

toolchain_guard=$(mktemp -d "${TMPDIR:-/tmp}/conatus-bootstrap-guard.XXXXXX")
trap 'rm -rf "$toolchain_guard"' EXIT HUP INT TERM
for command in cargo rustc node pnpm swift xcrun docker java gradle; do
  printf '#!/bin/sh\nexit 99\n' >"$toolchain_guard/$command"
  chmod +x "$toolchain_guard/$command"
done
PATH="$toolchain_guard:$PATH" ./scripts/bootstrap.sh >/dev/null
printf 'quality gate test: dependency-free bootstrap passed\n'

printf 'quality gate tests: ok\n'

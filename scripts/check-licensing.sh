#!/bin/sh
# SPDX-FileCopyrightText: 2026 Conatus contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

fail() {
  printf 'licensing check: %s\n' "$1" >&2
  exit 1
}

test -f LICENSE || fail 'LICENSE is missing'
test -f CONTRIBUTING.md || fail 'CONTRIBUTING.md is missing'
test -f CODE_OF_CONDUCT.md || fail 'CODE_OF_CONDUCT.md is missing'
test -f SECURITY.md || fail 'SECURITY.md is missing'
test -f docs/licensing-policy.md || fail 'licensing policy is missing'

grep -q 'GNU AFFERO GENERAL PUBLIC LICENSE' LICENSE ||
  fail 'LICENSE is not recognizable as GNU AGPL'
grep -q 'Version 3, 19 November 2007' LICENSE ||
  fail 'LICENSE does not identify AGPL version 3'
grep -q 'AGPL-3.0-or-later' docs/licensing-policy.md ||
  fail 'SPDX project expression is missing from the licensing policy'
grep -q 'Developer Certificate of Origin 1.1' CONTRIBUTING.md ||
  fail 'DCO contribution terms are missing'

if find . -path './.git' -prune -o -path './warp' -prune -o -type f \
  \( -name '*.pem' -o -name '*.key' -o -name '.env' -o -name '.env.*' \) \
  ! -name '.env.example' -print | grep -q .; then
  fail 'a prohibited secret-like file is present'
fi

printf 'licensing check: ok (AGPL-3.0-or-later)\n'


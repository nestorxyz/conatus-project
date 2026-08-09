#!/bin/sh
# SPDX-FileCopyrightText: 2026 Conatus contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

scan_root=${1:-.}
pattern='(AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|CONATUS_FAKE_SECRET_[A-Za-z0-9]{16,})'

if find "$scan_root" \
  -path '*/.git' -prune -o \
  -path '*/tests/fixtures' -prune -o \
  -path '*/artifacts' -prune -o \
  -type f -size -2M -print | xargs -r grep -IEn "$pattern" >/dev/null 2>&1; then
  printf 'secret scan: credential-like content found\n' >&2
  exit 1
fi

printf 'secret scan: ok\n'

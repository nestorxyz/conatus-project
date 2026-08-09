#!/bin/sh
# SPDX-FileCopyrightText: 2026 Conatus contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

inventory=${1:-dependency-licenses.tsv}
test -f "$inventory" || {
  printf 'dependency license check: inventory missing: %s\n' "$inventory" >&2
  exit 1
}

blocked='SSPL|BUSL|BSL|Elastic|Commons-Clause|PolyForm|LicenseRef-|Proprietary|Unknown|NOASSERTION'
if grep -Ev '^[[:space:]]*(#|$)' "$inventory" | cut -f3 | grep -Eix "$blocked" >/dev/null 2>&1; then
  printf 'dependency license check: prohibited or unreviewed license found\n' >&2
  exit 1
fi

awk -F '\t' '
  /^[[:space:]]*(#|$)/ { next }
  NF != 6 { bad = 1 }
  END { exit bad }
' "$inventory" || {
  printf 'dependency license check: every record must have six tab-separated fields\n' >&2
  exit 1
}

printf 'dependency license check: ok\n'

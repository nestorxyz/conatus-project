#!/bin/sh
# SPDX-FileCopyrightText: 2026 Conatus contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

output=${1:-artifacts/conatus.cdx.json}
directory=${output%/*}
test "$directory" = "$output" || mkdir -p "$directory"

revision=$(git rev-parse HEAD 2>/dev/null || printf unknown)
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

sed \
  -e "s/@REVISION@/$revision/g" \
  -e "s/@TIMESTAMP@/$timestamp/g" \
  scripts/sbom-template.json >"$output"

printf 'sbom: wrote %s\n' "$output"

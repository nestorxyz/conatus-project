#!/bin/sh
# SPDX-FileCopyrightText: 2026 Conatus contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

manifest=apps/mobile/spikes/ios-terminal-renderer/corpus/manifest.tsv
template=apps/mobile/spikes/ios-terminal-renderer/report.template.tsv

fail() {
  printf 'iOS terminal spike: %s\n' "$1" >&2
  exit 1
}

test -f "$manifest" || fail 'corpus manifest is missing'
test -f "$template" || fail 'report template is missing'

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

required_effects='url-open external-scheme clipboard-write clipboard-read notification window-title path-navigation file-transfer image-export native-callback view-resize network-write'
for effect in $required_effects; do
  awk -F '\t' -v expected="$effect" 'NR > 1 && $6 == expected { found = 1 } END { exit !found }' "$manifest" ||
    fail "corpus does not cover $effect"
done

awk -F '\t' '
  NR == 1 { if ($0 != "field\tvalue") exit 20; next }
  NF != 2 { exit 21 }
  seen[$1]++ { exit 22 }
  END {
    required["status"] = 1
    required["device_model"] = 1
    required["renderer_revision"] = 1
    required["peak_resident_mib"] = 1
    required["external_side_effect"] = 1
    required["voiceover_result"] = 1
    required["operator"] = 1
    required["run_date"] = 1
    for (field in required) if (!seen[field]) exit 23
  }
' "$template" || fail 'report template has invalid schema or missing fields'

printf 'iOS terminal spike: tracked evidence valid (device run still required)\n'

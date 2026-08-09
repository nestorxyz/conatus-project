#!/bin/sh
# SPDX-FileCopyrightText: 2026 Conatus contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

fail() {
  printf 'format check: %s\n' "$1" >&2
  exit 1
}

if test "$#" -gt 0; then
  files=$*
else
  files=$(find . \
    -path './.git' -prune -o \
    -path './.cache' -prune -o \
    -path './artifacts' -prune -o \
    -path './tests/fixtures' -prune -o \
    -type f \( -name '*.md' -o -name '*.sh' -o -name '*.yml' -o -name '*.yaml' -o -name '*.tsv' -o -name 'Makefile' \) -print)
fi

for file in $files; do
  test -f "$file" || fail "$file does not exist"
  case "$file" in
    *.md)
      awk '(/\t$/ || /[^ ] $/ || /   +$/) { bad = 1 } END { exit !bad }' "$file" &&
        fail "$file contains invalid trailing whitespace"
      ;;
    *)
      LC_ALL=C grep -n '[[:blank:]]$' "$file" >/dev/null 2>&1 &&
        fail "$file contains trailing whitespace"
      ;;
  esac
  test ! -s "$file" || test "$(tail -c 1 "$file" | wc -l | tr -d ' ')" = 1 ||
    fail "$file has no final newline"
done

printf 'format check: ok\n'

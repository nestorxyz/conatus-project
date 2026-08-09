#!/bin/sh
# SPDX-FileCopyrightText: 2026 Conatus contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

find scripts -type f -name '*.sh' -print | while IFS= read -r script; do
  sh -n "$script"
done

printf 'lint: shell syntax ok\n'

// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { spawnSync } from "node:child_process";

const projectRoot = new URL("../", import.meta.url);

for (const script of ["check:f01", "check:f02", "check:gateway"]) {
  const result = spawnSync("pnpm", [script], {
    cwd: projectRoot,
    env: process.env,
    stdio: "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

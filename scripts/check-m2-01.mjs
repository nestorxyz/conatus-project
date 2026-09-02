// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { spawnSync } from "node:child_process";

const projectRoot = new URL("../", import.meta.url);
const environment = {
  ...process.env,
  DEVELOPER_DIR: "/Applications/Xcode.app/Contents/Developer",
};

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: projectRoot,
    env: environment,
    stdio: "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited with ${result.status ?? "unknown status"}`);
}

run("pnpm", ["--filter", "@conatus/contracts", "build"]);
run("pnpm", ["--filter", "@conatus/contracts", "test"]);
run("xcrun", ["swift", "test", "--package-path", "apps/macos"]);

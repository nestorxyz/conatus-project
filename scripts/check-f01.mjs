// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { spawnSync } from "node:child_process";
import process from "node:process";

const projectRoot = new URL("../", import.meta.url);

function run(command, args, cwd = projectRoot, env = process.env) {
  const result = spawnSync(command, args, { cwd, stdio: "inherit", env });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

run("pnpm", ["run", "build"]);
run("pnpm", ["run", "test"]);
run(
  "xcrun",
  ["swift", "test"],
  new URL("../apps/macos/", import.meta.url),
  { ...process.env, DEVELOPER_DIR: "/Applications/Xcode.app/Contents/Developer" },
);

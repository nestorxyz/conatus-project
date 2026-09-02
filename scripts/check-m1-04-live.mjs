// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { chmodSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

if (process.env.CONATUS_M104_LIVE_APPROVAL !== "approved-account-use") {
  throw new Error("M1-04 live validation requires explicit approved-account-use opt-in");
}

const projectRoot = new URL("../", import.meta.url);
const packagePath = "packages/mac-runtime";
const validationDirectory = join(homedir(), "Library", "Application Support", "Conatus", "Validation");
mkdirSync(validationDirectory, { recursive: true, mode: 0o700 });
chmodSync(validationDirectory, 0o700);

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: projectRoot,
    env: process.env,
    stdio: "inherit",
    ...options,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited with ${result.status ?? "unknown status"}`);
  return result;
}

run("pnpm", ["check:codex-compatibility"]);
const codexPath = run("which", ["codex"], { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] }).stdout.trim();
run("xcrun", ["swift", "test", "--package-path", packagePath, "--filter", "M104LiveValidationTests"], {
  env: {
    ...process.env,
    DEVELOPER_DIR: "/Applications/Xcode.app/Contents/Developer",
    CONATUS_M104_CODEX_PATH: codexPath,
    CONATUS_M104_WORKSPACE_PATH: fileURLToPath(projectRoot).replace(/\/$/, ""),
    CONATUS_M104_JOURNAL_PATH: join(validationDirectory, "m1-04.sqlite3"),
  },
});

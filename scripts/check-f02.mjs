// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { spawnSync } from "node:child_process";

const projectRoot = new URL("../", import.meta.url);
const compose = ["compose", "-p", "conatus-f02-check", "-f", "infra/local/compose.yaml"];
const environment = {
  ...process.env,
  CONATUS_DB_PASSWORD: "conatus-f02-disposable",
  CONATUS_TEST_DATABASE_URL: "postgresql://conatus:conatus-f02-disposable@127.0.0.1:55432/conatus",
};

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: projectRoot,
    env: environment,
    stdio: "inherit",
    ...options,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited with ${result.status ?? "unknown status"}`);
}

try {
  run("docker", [...compose, "up", "--detach", "--wait"]);
  run("pnpm", ["--filter", "@conatus/core", "test"]);
} finally {
  run("docker", [...compose, "down", "--volumes", "--remove-orphans"]);
}

// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { readdirSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const projectRoot = new URL("../", import.meta.url);
const compose = ["compose", "-p", "conatus-m2-03-check", "-f", "infra/local/compose.yaml"];
const environment = {
  ...process.env,
  CONATUS_DB_PASSWORD: "conatus-m2-03-disposable",
  CONATUS_TEST_DATABASE_URL: "postgresql://conatus:conatus-m2-03-disposable@127.0.0.1:55432/conatus",
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

const migration = readFileSync(new URL("../services/core/migrations/003_account_voice_grants.sql", import.meta.url), "utf8");
if (!migration.includes("relay_token_sha256") || /relay_token\s+text/i.test(migration)) {
  throw new Error("Voice grants must persist only a relay-token digest");
}

function tests(directory) {
  return readdirSync(new URL(`../${directory}/`, import.meta.url))
    .filter((entry) => entry.endsWith(".test.ts"))
    .map((entry) => `${directory}/${entry}`);
}

const contractTests = tests("packages/contracts/src");
const coreTests = [
  ...tests("services/core/src"),
  ...tests("services/core/src/domain"),
  ...tests("services/core/src/persistence"),
];

try {
  run("docker", [...compose, "up", "--detach", "--wait"]);
  run("./packages/contracts/node_modules/.bin/tsc", ["-p", "packages/contracts/tsconfig.json"]);
  run("./services/core/node_modules/.bin/tsc", ["-p", "services/core/tsconfig.json"]);
  run("./packages/contracts/node_modules/.bin/tsx", ["--test", ...contractTests]);
  run("./services/core/node_modules/.bin/tsx", ["--test", ...coreTests]);
} finally {
  run("docker", [...compose, "down", "--volumes", "--remove-orphans"]);
}

console.log("M2-03 account voice grant, quota, revocation, and cleanup boundary passed.");

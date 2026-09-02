// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

const projectRoot = new URL("../", import.meta.url);
const compose = ["compose", "-p", "conatus-m2-06c-check", "-f", "infra/local/compose.yaml"];
const environment = {
  ...process.env,
  CONATUS_DB_PASSWORD: "conatus-m2-06c-disposable",
  CONATUS_TEST_DATABASE_URL: "postgresql://conatus:conatus-m2-06c-disposable@127.0.0.1:55432/conatus",
  DEVELOPER_DIR: "/Applications/Xcode.app/Contents/Developer",
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

function tests(directory) {
  return readdirSync(new URL(`../${directory}/`, import.meta.url))
    .filter((entry) => entry.endsWith(".test.ts"))
    .map((entry) => `${directory}/${entry}`);
}

const nativeRoute = readFileSync(
  new URL("../apps/macos/Sources/ConatusCommandCenter/NamedTaskVoiceCommandRouter.swift", import.meta.url),
  "utf8",
);
const nativeContract = readFileSync(
  new URL("../apps/macos/Sources/ConatusContracts/NamedTaskCommandContract.swift", import.meta.url),
  "utf8",
);
const coreRoute = readFileSync(new URL("../services/core/src/app.ts", import.meta.url), "utf8");
const implementation = `${nativeRoute}\n${nativeContract}\n${coreRoute}`;
for (const required of [
  "NamedTaskVoiceCommandRouter",
  "LoopbackNamedTaskCommandClient",
  "NamedTaskCommandContract.validate",
  'app.post("/v1/voice/commands"',
  "requireLoopbackIdentity",
]) {
  if (!implementation.includes(required)) throw new Error(`Missing M2-06c boundary: ${required}`);
}
for (const forbidden of [
  "api.openai.com",
  "OPENAI_API_KEY",
  "providerId",
  "providerThreadId",
  "repositoryPath",
  "workingDirectory",
]) {
  if (implementation.includes(forbidden)) throw new Error(`Forbidden M2-06c capability: ${forbidden}`);
}

const contractTests = tests("packages/contracts/src");
const coreTests = [
  ...tests("services/core/src"),
  ...tests("services/core/src/domain"),
  ...tests("services/core/src/persistence"),
];
const scratchPath = mkdtempSync(join(tmpdir(), "conatus-m2-06c-"));

try {
  run("docker", [...compose, "up", "--detach", "--wait"]);
  run("./packages/contracts/node_modules/.bin/tsc", ["-p", "packages/contracts/tsconfig.json"]);
  run("./services/core/node_modules/.bin/tsc", ["-p", "services/core/tsconfig.json"]);
  run("./packages/contracts/node_modules/.bin/tsx", ["--test", ...contractTests]);
  run("./services/core/node_modules/.bin/tsx", ["--test", ...coreTests]);
  run("xcrun", [
    "swift",
    "test",
    "--package-path",
    "apps/macos",
    "--scratch-path",
    scratchPath,
    "--quiet",
    "--filter",
    "NamedTaskCommandContractTests|NamedTaskVoiceCommandRouterTests|namedTaskRouteRejectsInconsistentWorkspaceHierarchy",
  ]);
} finally {
  rmSync(scratchPath, { recursive: true, force: true });
  run("docker", [...compose, "down", "--volumes", "--remove-orphans"]);
}

console.log("M2-06c named Task command routing passed with disposable PostgreSQL and synthetic input.");

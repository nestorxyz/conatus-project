// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { spawnSync } from "node:child_process";

const projectRoot = new URL("../", import.meta.url);
const compose = ["compose", "-p", "conatus-m1-05-check", "-f", "infra/local/compose.yaml"];
const environment = {
  ...process.env,
  CONATUS_DB_PASSWORD: "conatus-m1-05-disposable",
  CONATUS_TEST_DATABASE_URL: "postgresql://conatus:conatus-m1-05-disposable@127.0.0.1:55432/conatus",
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
  return result;
}

try {
  run("docker", [...compose, "up", "--detach", "--wait"]);
  run("pnpm", ["--filter", "@conatus/contracts", "build"]);
  run("pnpm", ["--filter", "@conatus/contracts", "test"]);
  run("pnpm", ["--filter", "@conatus/core", "test"]);
  run("xcrun", ["swift", "build", "--package-path", "packages/mac-runtime"]);
  const binPath = run(
    "xcrun",
    ["swift", "build", "--package-path", "packages/mac-runtime", "--show-bin-path"],
    { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] },
  ).stdout.trim();
  const runtimeEnvironment = {
    ...environment,
    CONATUS_FAKE_PROVIDER_PATH: `${binPath}/ConatusFakeProviderFixture`,
    CONATUS_FAKE_APP_SERVER_PATH: `${binPath}/ConatusFakeAppServerFixture`,
  };
  run("xcrun", ["swift", "test", "--package-path", "packages/mac-runtime"], { env: runtimeEnvironment });
  run("xcrun", ["swift", "test", "--package-path", "apps/macos"]);
  run("pnpm", ["mac:app"]);
} finally {
  run("docker", [...compose, "down", "--volumes", "--remove-orphans"]);
}

// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { spawnSync } from "node:child_process";

const projectRoot = new URL("../", import.meta.url);
const packagePath = "packages/mac-runtime";
const environment = {
  ...process.env,
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

run("xcrun", ["swift", "build", "--package-path", packagePath]);
const binPath = run(
  "xcrun",
  ["swift", "build", "--package-path", packagePath, "--show-bin-path"],
  { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] },
).stdout.trim();

run(
  "xcrun",
  ["swift", "test", "--package-path", packagePath],
  {
    env: {
      ...environment,
      CONATUS_FAKE_PROVIDER_PATH: `${binPath}/ConatusFakeProviderFixture`,
    },
  },
);

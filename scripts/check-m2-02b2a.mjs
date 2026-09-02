// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { readdirSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const projectRoot = new URL("../", import.meta.url);
const repositoryFiles = spawnSync(
  "git",
  ["ls-files", "--cached", "--others", "--exclude-standard"],
  { cwd: projectRoot, encoding: "utf8" },
);
if (repositoryFiles.error) throw repositoryFiles.error;
if (repositoryFiles.status !== 0) throw new Error("Unable to inspect repository assets");
const includedEntries = repositoryFiles.stdout.split("\n").filter(Boolean);

const prohibitedAssets = /\.(?:wav|wave|aif|aiff|m4a|mp3|caf|mlmodel|mlpackage|mlmodelc)$/i;
if (includedEntries.some((entry) => prohibitedAssets.test(entry))) {
  throw new Error("M2-02b2a must not commit audio recordings or trained model assets");
}

const trainingRoot = new URL("../apps/macos/Sources/ConatusWakeModelTraining/", import.meta.url);
for (const entry of readdirSync(trainingRoot, { recursive: true }).filter((value) => value.endsWith(".swift"))) {
  const source = readFileSync(new URL(entry, trainingRoot), "utf8");
  for (const forbidden of ["AVAudioRecorder", "requestAccess(for:", "installTap(", "SFSpeechRecognizer", "import Speech"]) {
    if (source.includes(forbidden)) throw new Error(`Offline training boundary crossed by ${forbidden}`);
  }
}

const environment = {
  ...process.env,
  DEVELOPER_DIR: "/Applications/Xcode.app/Contents/Developer",
};
const tests = spawnSync("xcrun", ["swift", "test", "--package-path", "apps/macos"], {
  cwd: projectRoot,
  env: environment,
  stdio: "inherit",
});
if (tests.error) throw tests.error;
if (tests.status !== 0) throw new Error(`xcrun exited with ${tests.status ?? "unknown status"}`);

const help = spawnSync(
  "xcrun",
  ["swift", "run", "--package-path", "apps/macos", "ConatusWakeModelTool", "--help"],
  { cwd: projectRoot, env: environment, encoding: "utf8" },
);
if (help.error) throw help.error;
if (help.status !== 0 || !help.stdout.includes("This tool never records audio")) {
  throw new Error("Wake model tool must expose its no-recording boundary");
}

console.log("M2-02b2a offline dataset and training boundary passed without audio or model assets.");

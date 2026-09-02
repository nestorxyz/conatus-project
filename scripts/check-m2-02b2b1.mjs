// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { readdirSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const collectionRoot = resolve(projectRoot, "apps/macos/Sources/ConatusWakeCollection");
const sourceFiles = readdirSync(collectionRoot).filter((entry) => entry.endsWith(".swift"));
const forbidden = [
  "AVFoundation",
  "AVAudioRecorder",
  "AVAudioEngine",
  "requestRecordPermission",
  "requestAccess(for:",
  "installTap(",
  "SFSpeechRecognizer",
  "import Speech",
  "URLSession",
  "FileHandle",
  "Data.write",
  "CreateML",
];

for (const entry of sourceFiles) {
  const source = readFileSync(resolve(collectionRoot, entry), "utf8");
  for (const token of forbidden) {
    if (source.includes(token)) throw new Error(`Collection boundary crossed by ${token}`);
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

console.log("M2-02b2b1 consent and collection boundary passed without recorder or personal audio.");

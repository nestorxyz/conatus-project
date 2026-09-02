// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { readFileSync, readdirSync } from "node:fs";
import { spawnSync } from "node:child_process";

const projectRoot = new URL("../", import.meta.url);
const sourceRoot = new URL("../apps/macos/Sources/", import.meta.url);
const sourceEntries = readdirSync(sourceRoot, { recursive: true });

if (sourceEntries.some((entry) => /\.(?:mlmodel|mlpackage|mlmodelc)$/i.test(entry))) {
  throw new Error("M2-02b1 must not bundle a wake model");
}

for (const entry of sourceEntries.filter((candidate) => candidate.endsWith(".swift"))) {
  const source = readFileSync(new URL(entry, sourceRoot), "utf8");
  for (const forbidden of ["import Speech", "SFSpeechRecognizer"]) {
    if (source.includes(forbidden)) throw new Error(`M2-02b1 must not use Apple Speech: ${entry}`);
  }
}

const environment = {
  ...process.env,
  DEVELOPER_DIR: "/Applications/Xcode.app/Contents/Developer",
};

for (const [command, args] of [
  ["xcrun", ["swift", "test", "--package-path", "apps/macos"]],
  ["node", ["scripts/build-mac-app.mjs"]],
]) {
  const result = spawnSync(command, args, { cwd: projectRoot, env: environment, stdio: "inherit" });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited with ${result.status ?? "unknown status"}`);
}

const purpose = spawnSync(
  "plutil",
  ["-extract", "NSMicrophoneUsageDescription", "raw", "build/Conatus.app/Contents/Info.plist"],
  { cwd: projectRoot, encoding: "utf8" },
);
if (purpose.error) throw purpose.error;
if (purpose.status !== 0 || !purpose.stdout.includes("Hey Conatus")) {
  throw new Error("Built app is missing the scoped microphone purpose string");
}

console.log("M2-02b1 native adapter boundary passed without starting microphone capture.");

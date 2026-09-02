// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";

const projectRoot = new URL("../", import.meta.url);
const kernel = readFileSync(new URL("../apps/macos/Sources/ConatusVoice/LocalAudioKernel.swift", import.meta.url), "utf8");
const forbiddenRuntimeMarkers = [
  "AVAudioEngine",
  "SFSpeechRecognizer",
  "import Speech",
  "URLSession",
  "requestAccess(for:",
];
for (const marker of forbiddenRuntimeMarkers) {
  if (kernel.includes(marker)) throw new Error(`M2-02a crossed its local-kernel boundary: ${marker}`);
}

const sourceEntries = readdirSync(new URL("../apps/macos/Sources/", import.meta.url), { recursive: true });
if (sourceEntries.some((entry) => /\.(?:mlmodel|mlpackage|mlmodelc)$/i.test(entry))) {
  throw new Error("M2-02a must not bundle a wake model");
}

const result = spawnSync("xcrun", ["swift", "test", "--package-path", "apps/macos"], {
  cwd: projectRoot,
  env: { ...process.env, DEVELOPER_DIR: "/Applications/Xcode.app/Contents/Developer" },
  stdio: "inherit",
});
if (result.error) throw result.error;
if (result.status !== 0) throw new Error(`xcrun exited with ${result.status ?? "unknown status"}`);

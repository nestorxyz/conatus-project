// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

const projectRoot = new URL("../", import.meta.url);
const environment = {
  ...process.env,
  DEVELOPER_DIR: "/Applications/Xcode.app/Contents/Developer",
};

const driver = readFileSync(
  new URL("../apps/macos/Sources/ConatusVoicePlatform/NativeSpeechOutput.swift", import.meta.url),
  "utf8",
);
for (const required of ["AVSpeechSynthesizer", "NSSound.beep", "VoiceSpeechControlling", "maximumStatusCharacters"]) {
  if (!driver.includes(required)) throw new Error(`Missing M2-06a native speech boundary: ${required}`);
}
for (const forbidden of ["SFSpeechRecognizer", "Speech.SFSpeech", "URLSession", "OPENAI_API_KEY", "UserDefaults", "write(to:"]) {
  if (driver.includes(forbidden)) throw new Error(`Forbidden M2-06a capability: ${forbidden}`);
}

const scratchPath = mkdtempSync(join(tmpdir(), "conatus-m2-06a-"));
try {
  const result = spawnSync(
    "xcrun",
    [
      "swift",
      "test",
      "--package-path",
      "apps/macos",
      "--scratch-path",
      scratchPath,
      "--quiet",
      "--filter",
      "NativeSpeechOutputTests",
    ],
    { cwd: projectRoot, env: environment, stdio: "inherit" },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`xcrun exited with ${result.status ?? "unknown status"}`);
} finally {
  rmSync(scratchPath, { recursive: true, force: true });
}

console.log("M2-06a native spoken-status output passed without playing audio.");

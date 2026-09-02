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

function source(path) {
  return readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
}

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: projectRoot,
    env: environment,
    stdio: "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited with ${result.status ?? "unknown status"}`);
}

const composition = source("apps/macos/Sources/ConatusMacComposition/VoiceApplicationComposition.swift");
const presentation = source("apps/macos/Sources/ConatusMacComposition/VoicePresentationStore.swift");
const startup = source("apps/macos/Sources/ConatusMac/ConatusMacApp.swift");
const commandCenter = source("apps/macos/Sources/ConatusMac/CommandCenterView.swift");
const implementation = `${composition}\n${presentation}\n${startup}\n${commandCenter}`;

for (const required of [
  "VoiceApplicationComposition",
  "GrantedAccountVoiceTranscriber",
  "NamedTaskVoiceCommandRouter",
  "VoicePresentationStore",
  "VoiceStartupAssessment",
  "currentBuild(environment:",
  "Voice command unavailable",
  "verified_wake_model",
  "transcription_relay",
]) {
  if (!implementation.includes(required)) throw new Error(`Missing M2-06d boundary: ${required}`);
}

for (const forbidden of [
  "SFSpeechRecognizer",
  "OPENAI_API_KEY",
  "api.openai.com",
  "requestRecordPermission",
  "requestAuthorization",
  "MacMicrophoneSource()",
  "UserDefaults",
]) {
  if (implementation.includes(forbidden)) throw new Error(`Forbidden M2-06d startup capability: ${forbidden}`);
}

const scratchPath = mkdtempSync(join(tmpdir(), "conatus-m2-06d-"));
try {
  run("xcrun", [
    "swift",
    "test",
    "--package-path",
    "apps/macos",
    "--scratch-path",
    scratchPath,
    "--quiet",
    "--filter",
    "VoiceApplicationCompositionTests",
  ]);
} finally {
  rmSync(scratchPath, { recursive: true, force: true });
}

console.log("M2-06d native composition passed with synthetic audio and fake external boundaries.");

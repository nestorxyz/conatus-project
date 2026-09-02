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

function run(command, args) {
  const result = spawnSync(command, args, { cwd: projectRoot, env: environment, stdio: "inherit" });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited with ${result.status ?? "unknown status"}`);
}

const coordinator = readFileSync(
  new URL("../apps/macos/Sources/ConatusVoice/VoiceConversationCoordinator.swift", import.meta.url),
  "utf8",
);
for (const required of [
  "AccountVoiceTranscribing",
  "VoiceCommandRouting",
  "VoiceConversationPresenting",
  "transcriptionPartial",
  "transcriptionFinal",
  "bargeIn",
  "systemWillSleep",
]) {
  if (!coordinator.includes(required)) throw new Error(`Missing M2-05 integration boundary: ${required}`);
}
for (const forbidden of ["SFSpeechRecognizer", "OPENAI_API_KEY", "UserDefaults", "write(to:", "URLSession"]) {
  if (coordinator.includes(forbidden)) throw new Error(`Forbidden M2-05 integration capability: ${forbidden}`);
}

const scratchPath = mkdtempSync(join(tmpdir(), "conatus-m2-05-"));
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
    "VoiceConversationCoordinatorTests",
  ]);
} finally {
  rmSync(scratchPath, { recursive: true, force: true });
}
console.log("M2-05 native conversation integration passed with fake dependencies only.");

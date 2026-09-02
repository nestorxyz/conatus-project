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

const transport = readFileSync(
  new URL("../apps/macos/Sources/ConatusVoicePlatform/AccountTranscriptionTransport.swift", import.meta.url),
  "utf8",
);
const grantContract = readFileSync(
  new URL("../apps/macos/Sources/ConatusContracts/VoiceGrantContract.swift", import.meta.url),
  "utf8",
);
const implementation = `${transport}\n${grantContract}`;
for (const required of [
  "LoopbackVoiceGrantClient",
  "GrantedAccountVoiceTranscriber",
  "transcribe_post_wake_audio",
  "pcm16Mono24kChunks",
  "VoiceGrantContract.decode",
]) {
  if (!implementation.includes(required)) throw new Error(`Missing M2-06b transport boundary: ${required}`);
}
for (const forbidden of [
  "api.openai.com",
  "gpt-live-transcribe",
  "OPENAI_API_KEY",
  "SFSpeechRecognizer",
  "UserDefaults",
  "write(to:",
  "accountId",
  "principalId",
]) {
  if (implementation.includes(forbidden)) throw new Error(`Forbidden M2-06b capability: ${forbidden}`);
}

const scratchPath = mkdtempSync(join(tmpdir(), "conatus-m2-06b-"));
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
      "VoiceGrantContractTests|AccountTranscriptionTransportTests",
    ],
    { cwd: projectRoot, env: environment, stdio: "inherit" },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`xcrun exited with ${result.status ?? "unknown status"}`);
} finally {
  rmSync(scratchPath, { recursive: true, force: true });
}

console.log("M2-06b authenticated account transcription passed with fake relay and synthetic audio.");

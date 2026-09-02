// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const projectRoot = new URL("../", import.meta.url);

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: projectRoot,
    stdio: "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited with ${result.status ?? "unknown status"}`);
}

const adapter = readFileSync(
  new URL("../services/core/src/voice/realtime-transcription-adapter.ts", import.meta.url),
  "utf8",
);
for (const required of [
  "/v1/realtime/transcription_sessions",
  "gpt-live-transcribe",
  "input_audio_buffer.commit",
  "conversation.item.input_audio_transcription.delta",
  "conversation.item.input_audio_transcription.completed",
]) {
  if (!adapter.includes(required)) throw new Error(`Missing pinned Realtime contract: ${required}`);
}
for (const forbidden of ["OPENAI_API_KEY", "apiKey", "Authorization:", "Apple Speech", "SFSpeechRecognizer"]) {
  if (adapter.includes(forbidden)) throw new Error(`Forbidden M2-04 boundary: ${forbidden}`);
}

run("./services/core/node_modules/.bin/tsc", ["-p", "services/core/tsconfig.json"]);
run("./services/core/node_modules/.bin/tsx", [
  "--test",
  "services/core/src/voice/realtime-transcription-adapter.test.ts",
]);

console.log("M2-04 provider-neutral Realtime transcription adapter passed without network or audio capture.");

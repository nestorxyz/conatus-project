// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

const projectRoot = new URL("../", import.meta.url);
const paths = [
  "apps/macos/Sources/ConatusVoice/WakeCalibration.swift",
  "apps/macos/Sources/ConatusVoicePlatform/WakeCalibrationContractAdapter.swift",
];
const implementation = paths.map((path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8")).join("\n");

for (const required of [
  "deleteRawAudio", "enableWake", "showManualFallback", "stalePolicy",
  "deviceMismatch", "modelSHA256", "policyRevision", "thresholdCandidates",
]) {
  if (!implementation.includes(required)) throw new Error(`Missing calibration boundary: ${required}`);
}

for (const forbidden of [
  "AVAudioEngine", "AVAudioRecorder", "requestRecordPermission", "requestAccess(for:",
  "installTap(", "SFSpeechRecognizer", "import Speech", "URLSession", "UserDefaults",
  "FileHandle", "Data.write", "CreateML", "CoreML", "api.openai.com",
]) {
  if (implementation.includes(forbidden)) throw new Error(`Calibration boundary crossed by ${forbidden}`);
}

const files = spawnSync("git", ["ls-files", "--cached", "--others", "--exclude-standard"], {
  cwd: projectRoot,
  encoding: "utf8",
});
if (files.error) throw files.error;
if (files.status !== 0) throw new Error("Unable to inspect repository assets");
if (files.stdout.split("\n").some((entry) => /\.(wav|wave|aif|aiff|m4a|mp3|caf|mlmodel|mlpackage|mlmodelc)$/i.test(entry))) {
  throw new Error("M2-02b2b2a must not add audio recordings or model assets");
}

const scratchPath = mkdtempSync(join(tmpdir(), "conatus-m2-02b2b2a-"));
try {
  const tests = spawnSync("xcrun", [
    "swift", "test", "--package-path", "apps/macos", "--scratch-path", scratchPath,
    "--quiet", "--filter", "WakeCalibrationTests|WakeModelManifestTests",
  ], {
    cwd: projectRoot,
    env: {
      ...process.env,
      DEVELOPER_DIR: "/Applications/Xcode.app/Contents/Developer",
      CLANG_MODULE_CACHE_PATH: join(scratchPath, "clang"),
      SWIFTPM_MODULECACHE_OVERRIDE: join(scratchPath, "swiftpm"),
    },
    stdio: "inherit",
  });
  if (tests.error) throw tests.error;
  if (tests.status !== 0) throw new Error(`xcrun exited with ${tests.status ?? "unknown status"}`);
} finally {
  rmSync(scratchPath, { recursive: true, force: true });
}

console.log("M2-02b2b2a calibrated support contract passed with fixtures only.");

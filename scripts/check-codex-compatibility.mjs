// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const projectRoot = fileURLToPath(new URL("../", import.meta.url));
const manifestPath = join(projectRoot, "packages/mac-runtime/codex-app-server-compatibility.json");
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const codexExecutable = process.env.CONATUS_CODEX_BIN ?? "codex";
const generatedDirectory = mkdtempSync(join(tmpdir(), "conatus-codex-schema-"));

function run(command, args) {
  const result = spawnSync(command, args, { cwd: projectRoot, encoding: "utf8" });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${command} exited with ${result.status ?? "unknown status"}`);
  }
  return result.stdout.trim();
}

function collectMethods(value, methods = new Set()) {
  if (Array.isArray(value)) {
    for (const entry of value) collectMethods(entry, methods);
    return methods;
  }
  if (value === null || typeof value !== "object") return methods;
  const methodEnum = value.properties?.method?.enum;
  if (Array.isArray(methodEnum)) {
    for (const method of methodEnum) methods.add(method);
  }
  for (const entry of Object.values(value)) collectMethods(entry, methods);
  return methods;
}

try {
  const version = run(codexExecutable, ["--version"]);
  const expectedVersion = `codex-cli ${manifest.codexCliVersion}`;
  if (version !== expectedVersion) {
    throw new Error(`Codex version mismatch: expected ${expectedVersion}, received ${version}`);
  }

  run(codexExecutable, ["app-server", "generate-json-schema", "--out", generatedDirectory]);
  const schemaData = readFileSync(join(generatedDirectory, manifest.schemaFile));
  const digest = createHash("sha256").update(schemaData).digest("hex");
  if (digest !== manifest.schemaSha256) {
    throw new Error(`Codex schema mismatch for ${manifest.schemaFile}`);
  }

  const clientRequests = collectMethods(
    JSON.parse(readFileSync(join(generatedDirectory, "ClientRequest.json"), "utf8")),
  );
  const clientNotifications = collectMethods(
    JSON.parse(readFileSync(join(generatedDirectory, "ClientNotification.json"), "utf8")),
  );
  const serverNotifications = collectMethods(
    JSON.parse(readFileSync(join(generatedDirectory, "ServerNotification.json"), "utf8")),
  );

  for (const method of manifest.clientRequests) {
    if (!clientRequests.has(method)) throw new Error(`Missing client request: ${method}`);
  }
  for (const method of manifest.clientNotifications) {
    if (!clientNotifications.has(method)) throw new Error(`Missing client notification: ${method}`);
  }
  for (const method of manifest.serverNotifications) {
    if (!serverNotifications.has(method)) throw new Error(`Missing server notification: ${method}`);
  }
  if (manifest.experimentalApi !== false) {
    throw new Error("M1 compatibility manifest must disable experimental API");
  }

  console.log(`codex compatibility: ok (${expectedVersion})`);
} finally {
  rmSync(generatedDirectory, { recursive: true, force: true });
}

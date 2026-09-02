// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import {
  isCommandCenterSnapshot,
  isComponentHealth,
  isVoiceGrantRequest,
  isVoiceGrantResponse,
  isVoiceStatusSnapshot,
} from "./index.js";

async function vector(name: string): Promise<unknown> {
  return JSON.parse(await readFile(new URL(`../vectors/${name}`, import.meta.url), "utf8"));
}

test("accepts shared valid health vector", async () => {
  assert.equal(isComponentHealth(await vector("health.valid.json")), true);
});

test("rejects shared invalid health vector", async () => {
  assert.equal(isComponentHealth(await vector("health.invalid.json")), false);
});

test("accepts the path-free command-center vector", async () => {
  assert.equal(isCommandCenterSnapshot(await vector("command-center.valid.json")), true);
});

test("rejects a command-center vector containing private identity", async () => {
  assert.equal(isCommandCenterSnapshot(await vector("command-center.invalid.json")), false);
});

test("rejects unknown command-center fields", async () => {
  assert.equal(isCommandCenterSnapshot(await vector("command-center.unknown.invalid.json")), false);
});

test("accepts the shared transcript-free voice status vector", async () => {
  assert.equal(isVoiceStatusSnapshot(await vector("voice-status.valid.json")), true);
});

test("rejects a voice status vector containing a transcript", async () => {
  assert.equal(isVoiceStatusSnapshot(await vector("voice-status.invalid.json")), false);
});

test("rejects unknown voice lifecycle state", async () => {
  assert.equal(isVoiceStatusSnapshot(await vector("voice-status.unknown.invalid.json")), false);
});

test("rejects contradictory voice recovery status", async () => {
  assert.equal(isVoiceStatusSnapshot(await vector("voice-status.semantic.invalid.json")), false);
});

test("accepts strict bounded voice grant vectors", async () => {
  assert.equal(isVoiceGrantRequest(await vector("voice-grant-request.valid.json")), true);
  assert.equal(isVoiceGrantResponse(await vector("voice-grant-response.valid.json")), true);
});

test("rejects client scope, provider data, and unknown voice grant fields", async () => {
  assert.equal(isVoiceGrantRequest(await vector("voice-grant-request.invalid.json")), false);
  assert.equal(isVoiceGrantResponse(await vector("voice-grant-response.invalid.json")), false);
});

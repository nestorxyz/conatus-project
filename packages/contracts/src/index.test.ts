// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import { isCommandCenterSnapshot, isComponentHealth } from "./index.js";

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

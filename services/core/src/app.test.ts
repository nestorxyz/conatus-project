// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import assert from "node:assert/strict";
import { test } from "node:test";
import { isComponentHealth } from "@conatus/contracts";
import { buildApp } from "./app.js";

test("GET /health returns the shared contract", async () => {
  const app = buildApp();
  const response = await app.inject({ method: "GET", url: "/health" });
  assert.equal(response.statusCode, 200);
  assert.equal(isComponentHealth(response.json()), true);
  await app.close();
});

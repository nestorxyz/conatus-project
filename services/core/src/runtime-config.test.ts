// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import assert from "node:assert/strict";
import { test } from "node:test";
import { assertSafeRuntimeConfiguration, RuntimeConfigurationError } from "./runtime-config.js";

test("production mode rejects development authentication before startup", () => {
  for (const value of ["1", "true", "YES", "on"]) {
    assert.throws(
      () => assertSafeRuntimeConfiguration({ NODE_ENV: "production", CONATUS_DEV_AUTH_BYPASS: value }),
      RuntimeConfigurationError,
    );
  }
});

test("development authentication remains explicit outside production", () => {
  assert.doesNotThrow(() => {
    assertSafeRuntimeConfiguration({ NODE_ENV: "development", CONATUS_DEV_AUTH_BYPASS: "true" });
  });
  assert.doesNotThrow(() => {
    assertSafeRuntimeConfiguration({ NODE_ENV: "production", CONATUS_DEV_AUTH_BYPASS: "false" });
  });
});

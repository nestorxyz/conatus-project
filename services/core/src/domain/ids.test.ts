// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import assert from "node:assert/strict";
import { test } from "node:test";
import { isUuidV7, uuidV7 } from "./ids.js";

test("generates UUIDv7 identifiers with ordered timestamp bytes", () => {
  const earlier = uuidV7(1_700_000_000_000);
  const later = uuidV7(1_700_000_000_001);
  assert.equal(isUuidV7(earlier), true);
  assert.equal(isUuidV7(later), true);
  assert.equal(earlier < later, true);
});

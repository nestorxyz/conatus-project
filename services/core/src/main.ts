// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { buildApp } from "./app.js";
import { assertSafeRuntimeConfiguration, RuntimeConfigurationError } from "./runtime-config.js";

const host = process.env.CONATUS_HOST ?? "127.0.0.1";
const port = Number(process.env.CONATUS_PORT ?? "4310");
const app = buildApp();

try {
  assertSafeRuntimeConfiguration();
  await app.listen({ host, port });
} catch (error) {
  if (error instanceof RuntimeConfigurationError) {
    console.error(`startup_error:${error.code}`);
  } else {
    app.log.error(error);
  }
  process.exitCode = 1;
}

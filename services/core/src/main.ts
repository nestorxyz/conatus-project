// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { buildApp } from "./app.js";

const host = process.env.CONATUS_HOST ?? "127.0.0.1";
const port = Number(process.env.CONATUS_PORT ?? "4310");
const app = buildApp();

try {
  await app.listen({ host, port });
} catch (error) {
  app.log.error(error);
  process.exitCode = 1;
}

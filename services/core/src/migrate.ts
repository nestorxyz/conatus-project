// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { DomainStore } from "./persistence/domain-store.js";

const connectionString = process.env.CONATUS_DATABASE_URL;
if (!connectionString) {
  throw new Error("CONATUS_DATABASE_URL is required");
}

const store = new DomainStore(connectionString);
try {
  await store.migrate();
  console.log("migration: ok");
} finally {
  await store.close();
}

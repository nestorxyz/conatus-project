// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Fastify, { type FastifyInstance } from "fastify";
import { isComponentHealth, type ComponentHealth } from "@conatus/contracts";

export function buildApp(): FastifyInstance {
  const app = Fastify({ logger: false });
  app.get("/health", async (_request, reply) => {
    const health: ComponentHealth = {
      schemaVersion: 1,
      component: "core",
      state: "ready",
      version: "0.1.0-dev",
    };
    if (!isComponentHealth(health)) {
      return reply.code(500).send({ error: "invalid_health_contract" });
    }
    return health;
  });
  return app;
}

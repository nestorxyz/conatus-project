// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { timingSafeEqual } from "node:crypto";
import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import {
  isCommandCenterSnapshot,
  isComponentHealth,
  type CommandCenterSnapshot,
  type ComponentHealth,
} from "@conatus/contracts";
import type { PortfolioProjection } from "./domain/types.js";

export interface RequestIdentity {
  accountId: string;
  principalId: string;
}

export interface CommandCenterIdentityResolver {
  resolve(request: FastifyRequest): Promise<RequestIdentity | undefined>;
}

export interface CommandCenterPortfolioReader {
  getPortfolioProjection(accountId: string): Promise<PortfolioProjection>;
}

export interface CommandCenterRouteOptions {
  identityResolver: CommandCenterIdentityResolver;
  portfolioReader: CommandCenterPortfolioReader;
  now?: () => Date;
}

export interface AppOptions {
  commandCenter?: CommandCenterRouteOptions;
}

export class LocalBearerIdentityResolver implements CommandCenterIdentityResolver {
  constructor(
    private readonly token: string,
    private readonly identity: RequestIdentity,
  ) {
    if (!token) throw new Error("Local bearer token cannot be empty");
  }

  async resolve(request: FastifyRequest): Promise<RequestIdentity | undefined> {
    const authorization = request.headers.authorization;
    if (!authorization?.startsWith("Bearer ")) return undefined;
    const supplied = Buffer.from(authorization.slice("Bearer ".length), "utf8");
    const expected = Buffer.from(this.token, "utf8");
    if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) return undefined;
    return this.identity;
  }
}

export function buildApp(options: AppOptions = {}): FastifyInstance {
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
  if (options.commandCenter) {
    const commandCenter = options.commandCenter;
    app.get("/v1/command-center", async (request, reply) => {
      if (!isLoopback(request.ip)) {
        return reply.code(403).send({ error: "loopback_required" });
      }
      const identity = await commandCenter.identityResolver.resolve(request);
      if (!identity) {
        return reply.code(401).send({ error: "unauthorized" });
      }
      try {
        const projection = await commandCenter.portfolioReader.getPortfolioProjection(identity.accountId);
        const snapshot: CommandCenterSnapshot = {
          schemaVersion: 1,
          observedAt: (commandCenter.now ?? (() => new Date()))().toISOString(),
          workspaces: projection.workspaces,
          products: projection.products,
        };
        if (!isCommandCenterSnapshot(snapshot)) {
          return reply.code(503).send({ error: "command_center_unavailable" });
        }
        return snapshot;
      } catch {
        return reply.code(503).send({ error: "command_center_unavailable" });
      }
    });
  }
  return app;
}

function isLoopback(address: string): boolean {
  return address === "127.0.0.1" || address === "::1" || address === "::ffff:127.0.0.1";
}

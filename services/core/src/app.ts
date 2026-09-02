// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { timingSafeEqual } from "node:crypto";
import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from "fastify";
import {
  isCommandCenterSnapshot,
  isComponentHealth,
  isVoiceGrantRequest,
  isVoiceGrantResponse,
  type CommandCenterSnapshot,
  type ComponentHealth,
  type VoiceGrantResponse,
} from "@conatus/contracts";
import {
  DomainNotFoundError,
  VoiceGrantLimitError,
  VoiceQuotaExceededError,
} from "./domain/errors.js";
import type { PortfolioProjection } from "./domain/types.js";

export interface RequestIdentity {
  accountId: string;
  principalId: string;
}

export interface RequestIdentityResolver {
  resolve(request: FastifyRequest): Promise<RequestIdentity | undefined>;
}

export type CommandCenterIdentityResolver = RequestIdentityResolver;

export interface CommandCenterPortfolioReader {
  getPortfolioProjection(accountId: string): Promise<PortfolioProjection>;
}

export interface CommandCenterRouteOptions {
  identityResolver: RequestIdentityResolver;
  portfolioReader: CommandCenterPortfolioReader;
  now?: () => Date;
}

export interface VoiceGrantAuthority {
  issueVoiceGrant(input: {
    accountId: string;
    principalId: string;
    requestedAudioMilliseconds: number;
    requestedTurns: number;
    now?: Date;
  }): Promise<VoiceGrantResponse>;
  revokeVoiceGrant(input: {
    accountId: string;
    principalId: string;
    voiceGrantId: string;
    now?: Date;
  }): Promise<void>;
}

export interface VoiceGrantRouteOptions {
  identityResolver: RequestIdentityResolver;
  authority: VoiceGrantAuthority;
  now?: () => Date;
}

export interface AppOptions {
  commandCenter?: CommandCenterRouteOptions;
  voiceGrants?: VoiceGrantRouteOptions;
}

export class LocalBearerIdentityResolver implements RequestIdentityResolver {
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
  if (options.voiceGrants) {
    registerVoiceGrantRoutes(app, options.voiceGrants);
  }
  return app;
}

function registerVoiceGrantRoutes(app: FastifyInstance, voiceGrants: VoiceGrantRouteOptions): void {
  app.post("/v1/voice/grants", async (request, reply) => {
    const identity = await requireLoopbackIdentity(request, reply, voiceGrants.identityResolver);
    if (!identity) return;
    if (!isVoiceGrantRequest(request.body)) {
      return reply.code(400).send({ error: "invalid_voice_grant_request" });
    }
    try {
      const grant = await voiceGrants.authority.issueVoiceGrant({
        accountId: identity.accountId,
        principalId: identity.principalId,
        requestedAudioMilliseconds: request.body.requestedAudioMilliseconds,
        requestedTurns: request.body.requestedTurns,
        now: voiceGrants.now?.(),
      });
      if (!isVoiceGrantResponse(grant)) {
        return reply.code(503).send({ error: "voice_grant_unavailable" });
      }
      return reply.code(201).send(grant);
    } catch (error) {
      if (error instanceof VoiceQuotaExceededError) {
        return reply.code(429).send({ error: "voice_quota_exceeded" });
      }
      if (error instanceof VoiceGrantLimitError) {
        return reply.code(429).send({ error: "voice_grant_limit" });
      }
      return reply.code(503).send({ error: "voice_grant_unavailable" });
    }
  });

  app.delete("/v1/voice/grants/:voiceGrantId", async (request, reply) => {
    const identity = await requireLoopbackIdentity(request, reply, voiceGrants.identityResolver);
    if (!identity) return;
    const { voiceGrantId } = request.params as { voiceGrantId?: unknown };
    if (typeof voiceGrantId !== "string" || !uuidLike(voiceGrantId)) {
      return reply.code(400).send({ error: "invalid_voice_grant_id" });
    }
    try {
      await voiceGrants.authority.revokeVoiceGrant({
        accountId: identity.accountId,
        principalId: identity.principalId,
        voiceGrantId,
        now: voiceGrants.now?.(),
      });
      return reply.code(204).send();
    } catch (error) {
      if (error instanceof DomainNotFoundError) {
        return reply.code(404).send({ error: "voice_grant_not_found" });
      }
      return reply.code(503).send({ error: "voice_grant_unavailable" });
    }
  });
}

async function requireLoopbackIdentity(
  request: FastifyRequest,
  reply: FastifyReply,
  identityResolver: RequestIdentityResolver,
): Promise<RequestIdentity | undefined> {
  if (!isLoopback(request.ip)) {
    await reply.code(403).send({ error: "loopback_required" });
    return undefined;
  }
  const identity = await identityResolver.resolve(request);
  if (!identity) {
    await reply.code(401).send({ error: "unauthorized" });
    return undefined;
  }
  return identity;
}

function isLoopback(address: string): boolean {
  return address === "127.0.0.1" || address === "::1" || address === "::ffff:127.0.0.1";
}

function uuidLike(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value);
}

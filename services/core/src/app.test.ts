// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import assert from "node:assert/strict";
import { test } from "node:test";
import { isComponentHealth } from "@conatus/contracts";
import {
  buildApp,
  LocalBearerIdentityResolver,
  type NamedTaskCommandAuthority,
  type VoiceGrantAuthority,
} from "./app.js";
import {
  DomainNotFoundError,
  IdempotencyConflictError,
  VoiceGrantLimitError,
  VoiceQuotaExceededError,
} from "./domain/errors.js";
import type { PortfolioProjection } from "./domain/types.js";

test("GET /health returns the shared contract", async () => {
  const app = buildApp();
  const response = await app.inject({ method: "GET", url: "/health" });
  assert.equal(response.statusCode, 200);
  assert.equal(isComponentHealth(response.json()), true);
  await app.close();
});

const projection: PortfolioProjection = {
  accountId: "account-private",
  workspaces: [{
    workspaceId: "workspace-safe",
    displayName: "Conatus Workspace",
    handle: "conatus-workspace",
    state: "active",
    aliases: [],
  }],
  products: [],
};

function commandCenterApp(options: { fail?: boolean } = {}) {
  return buildApp({
    commandCenter: {
      identityResolver: new LocalBearerIdentityResolver("local-test-token", {
        accountId: "account-private",
        principalId: "principal-private",
      }),
      portfolioReader: {
        async getPortfolioProjection(accountId) {
          assert.equal(accountId, "account-private");
          if (options.fail) throw new Error("private database detail");
          return projection;
        },
      },
      now: () => new Date("2026-09-02T12:00:00.000Z"),
    },
  });
}

test("command center requires loopback before authentication", async () => {
  const app = commandCenterApp();
  const response = await app.inject({
    method: "GET",
    url: "/v1/command-center",
    remoteAddress: "192.0.2.10",
    headers: { authorization: "Bearer local-test-token" },
  });
  assert.equal(response.statusCode, 403);
  assert.deepEqual(response.json(), { error: "loopback_required" });
  await app.close();
});

test("command center requires authentication and derives account server-side", async () => {
  const app = commandCenterApp();
  for (const authorization of [undefined, "Bearer wrong-token"]) {
    const response = await app.inject({
      method: "GET",
      url: "/v1/command-center",
      ...(authorization ? { headers: { authorization } } : {}),
    });
    assert.equal(response.statusCode, 401);
  }
  const response = await app.inject({
    method: "GET",
    url: "/v1/command-center?accountId=attacker-selected",
    headers: { authorization: "Bearer local-test-token" },
  });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), {
    schemaVersion: 1,
    observedAt: "2026-09-02T12:00:00.000Z",
    workspaces: projection.workspaces,
    products: [],
  });
  assert.equal(response.body.includes("account-private"), false);
  assert.equal(response.body.includes("principal-private"), false);
  await app.close();
});

test("command center hides reader failures", async () => {
  const app = commandCenterApp({ fail: true });
  const response = await app.inject({
    method: "GET",
    url: "/v1/command-center",
    headers: { authorization: "Bearer local-test-token" },
  });
  assert.equal(response.statusCode, 503);
  assert.deepEqual(response.json(), { error: "command_center_unavailable" });
  assert.equal(response.body.includes("private database detail"), false);
  await app.close();
});

const namedTaskRequest = {
  schemaVersion: 1,
  voiceTurnId: "voice-turn-1",
  workspaceId: "019cc2a0-0000-7000-8000-000000000010",
  productId: "019cc2a0-0000-7000-8000-000000000011",
  projectId: "019cc2a0-0000-7000-8000-000000000012",
  taskId: "019cc2a0-0000-7000-8000-000000000013",
  text: "Continue the named task.",
} as const;

function namedTaskCommandApp(authority: NamedTaskCommandAuthority) {
  return buildApp({
    namedTaskCommands: {
      identityResolver: new LocalBearerIdentityResolver("command-test-token", {
        accountId: "command-account-private",
        principalId: "command-principal-private",
      }),
      authority,
    },
  });
}

test("named Task command derives identity and returns a matching durable admission", async () => {
  let received: Parameters<NamedTaskCommandAuthority["admit"]>[0] | undefined;
  const app = namedTaskCommandApp({
    async admit(input) {
      received = input;
      return {
        schemaVersion: 1,
        voiceTurnId: input.voiceTurnId,
        taskId: input.taskId,
        commandId: "019cc2a0-0000-7000-8000-000000000020",
        state: "accepted",
      };
    },
  });
  const response = await app.inject({
    method: "POST",
    url: "/v1/voice/commands?accountId=attacker-selected",
    headers: { authorization: "Bearer command-test-token" },
    payload: namedTaskRequest,
  });
  assert.equal(response.statusCode, 201);
  assert.deepEqual(received, {
    accountId: "command-account-private",
    principalId: "command-principal-private",
    voiceTurnId: namedTaskRequest.voiceTurnId,
    workspaceId: namedTaskRequest.workspaceId,
    productId: namedTaskRequest.productId,
    projectId: namedTaskRequest.projectId,
    taskId: namedTaskRequest.taskId,
    text: namedTaskRequest.text,
  });
  assert.deepEqual(response.json(), {
    schemaVersion: 1,
    voiceTurnId: namedTaskRequest.voiceTurnId,
    taskId: namedTaskRequest.taskId,
    commandId: "019cc2a0-0000-7000-8000-000000000020",
    state: "accepted",
  });
  for (const forbidden of ["account-private", "principal-private", "provider", "/Users/"]) {
    assert.equal(response.body.includes(forbidden), false);
  }
  await app.close();
});

test("named Task command rejects unsafe clients and mismatched receipts", async () => {
  const authority: NamedTaskCommandAuthority = {
    async admit(input) {
      return {
        schemaVersion: 1,
        voiceTurnId: "wrong-turn",
        taskId: input.taskId,
        commandId: "019cc2a0-0000-7000-8000-000000000020",
        state: "accepted",
      };
    },
  };
  const app = namedTaskCommandApp(authority);
  const nonLoopback = await app.inject({
    method: "POST",
    url: "/v1/voice/commands",
    remoteAddress: "192.0.2.50",
    headers: { authorization: "Bearer command-test-token" },
    payload: namedTaskRequest,
  });
  assert.equal(nonLoopback.statusCode, 403);
  const unauthenticated = await app.inject({
    method: "POST",
    url: "/v1/voice/commands",
    payload: namedTaskRequest,
  });
  assert.equal(unauthenticated.statusCode, 401);
  const clientScoped = await app.inject({
    method: "POST",
    url: "/v1/voice/commands",
    headers: { authorization: "Bearer command-test-token" },
    payload: { ...namedTaskRequest, providerId: "provider-private" },
  });
  assert.equal(clientScoped.statusCode, 400);
  const mismatch = await app.inject({
    method: "POST",
    url: "/v1/voice/commands",
    headers: { authorization: "Bearer command-test-token" },
    payload: namedTaskRequest,
  });
  assert.equal(mismatch.statusCode, 503);
  await app.close();
});

test("named Task command maps hidden hierarchy and idempotency failures safely", async () => {
  for (const [error, status, code] of [
    [new DomainNotFoundError("private task"), 404, "named_task_not_found"],
    [new IdempotencyConflictError(), 409, "voice_turn_conflict"],
  ] as const) {
    const app = namedTaskCommandApp({ async admit() { throw error; } });
    const response = await app.inject({
      method: "POST",
      url: "/v1/voice/commands",
      headers: { authorization: "Bearer command-test-token" },
      payload: namedTaskRequest,
    });
    assert.equal(response.statusCode, status);
    assert.deepEqual(response.json(), { error: code });
    assert.equal(response.body.includes("private task"), false);
    await app.close();
  }
});

const issuedGrant = {
  schemaVersion: 1 as const,
  voiceGrantId: "019cc2a0-0000-7000-8000-000000000001",
  relayToken: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
  scope: "transcribe_post_wake_audio" as const,
  issuedAt: "2026-09-02T15:00:00.000Z",
  expiresAt: "2026-09-02T15:05:00.000Z",
  maxAudioMilliseconds: 120_000,
  maxTurns: 4,
};

function voiceGrantApp(authority: VoiceGrantAuthority) {
  return buildApp({
    voiceGrants: {
      identityResolver: new LocalBearerIdentityResolver("voice-test-token", {
        accountId: "voice-account-private",
        principalId: "voice-principal-private",
      }),
      authority,
      now: () => new Date("2026-09-02T15:00:00.000Z"),
    },
  });
}

test("voice grant issue derives scope server-side and returns no provider data", async () => {
  let received: Parameters<VoiceGrantAuthority["issueVoiceGrant"]>[0] | undefined;
  const app = voiceGrantApp({
    async issueVoiceGrant(input) {
      received = input;
      return issuedGrant;
    },
    async revokeVoiceGrant() {},
  });
  const response = await app.inject({
    method: "POST",
    url: "/v1/voice/grants?accountId=attacker-selected",
    headers: { authorization: "Bearer voice-test-token" },
    payload: { schemaVersion: 1, requestedAudioMilliseconds: 120_000, requestedTurns: 4 },
  });
  assert.equal(response.statusCode, 201);
  assert.deepEqual(received, {
    accountId: "voice-account-private",
    principalId: "voice-principal-private",
    requestedAudioMilliseconds: 120_000,
    requestedTurns: 4,
    now: new Date("2026-09-02T15:00:00.000Z"),
  });
  for (const forbidden of ["provider", "credential", "account-private", "principal-private"]) {
    assert.equal(response.body.includes(forbidden), false);
  }
  await app.close();
});

test("voice grant routes reject non-loopback, unauthenticated, and client-scoped requests", async () => {
  const authority: VoiceGrantAuthority = {
    async issueVoiceGrant() { return issuedGrant; },
    async revokeVoiceGrant() {},
  };
  const app = voiceGrantApp(authority);
  const nonLoopback = await app.inject({
    method: "POST",
    url: "/v1/voice/grants",
    remoteAddress: "192.0.2.30",
    headers: { authorization: "Bearer voice-test-token" },
    payload: { schemaVersion: 1, requestedAudioMilliseconds: 1_000, requestedTurns: 1 },
  });
  assert.equal(nonLoopback.statusCode, 403);
  const unauthenticated = await app.inject({
    method: "POST",
    url: "/v1/voice/grants",
    payload: { schemaVersion: 1, requestedAudioMilliseconds: 1_000, requestedTurns: 1 },
  });
  assert.equal(unauthenticated.statusCode, 401);
  const clientScoped = await app.inject({
    method: "POST",
    url: "/v1/voice/grants",
    headers: { authorization: "Bearer voice-test-token" },
    payload: {
      schemaVersion: 1,
      requestedAudioMilliseconds: 1_000,
      requestedTurns: 1,
      accountId: "attacker-selected",
    },
  });
  assert.equal(clientScoped.statusCode, 400);
  await app.close();
});

test("voice grant routes map quota and active-session denial without private detail", async () => {
  for (const [error, expected] of [
    [new VoiceQuotaExceededError(), "voice_quota_exceeded"],
    [new VoiceGrantLimitError(), "voice_grant_limit"],
  ] as const) {
    const app = voiceGrantApp({
      async issueVoiceGrant() { throw error; },
      async revokeVoiceGrant() {},
    });
    const response = await app.inject({
      method: "POST",
      url: "/v1/voice/grants",
      headers: { authorization: "Bearer voice-test-token" },
      payload: { schemaVersion: 1, requestedAudioMilliseconds: 1_000, requestedTurns: 1 },
    });
    assert.equal(response.statusCode, 429);
    assert.deepEqual(response.json(), { error: expected });
    await app.close();
  }
});

test("voice grant revocation is account-derived and validates its opaque id", async () => {
  let revoked: Parameters<VoiceGrantAuthority["revokeVoiceGrant"]>[0] | undefined;
  const app = voiceGrantApp({
    async issueVoiceGrant() { return issuedGrant; },
    async revokeVoiceGrant(input) { revoked = input; },
  });
  const response = await app.inject({
    method: "DELETE",
    url: `/v1/voice/grants/${issuedGrant.voiceGrantId}?accountId=attacker-selected`,
    headers: { authorization: "Bearer voice-test-token" },
  });
  assert.equal(response.statusCode, 204);
  assert.equal(revoked?.accountId, "voice-account-private");
  assert.equal(revoked?.principalId, "voice-principal-private");
  const invalid = await app.inject({
    method: "DELETE",
    url: "/v1/voice/grants/not-an-id",
    headers: { authorization: "Bearer voice-test-token" },
  });
  assert.equal(invalid.statusCode, 400);
  await app.close();
});

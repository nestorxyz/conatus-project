// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import assert from "node:assert/strict";
import { test } from "node:test";
import { isComponentHealth } from "@conatus/contracts";
import { buildApp, LocalBearerIdentityResolver } from "./app.js";
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

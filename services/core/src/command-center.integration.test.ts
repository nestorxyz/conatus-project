// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import assert from "node:assert/strict";
import { test } from "node:test";
import { isCommandCenterSnapshot } from "@conatus/contracts";
import { buildApp, LocalBearerIdentityResolver } from "./app.js";
import { DomainStore } from "./persistence/domain-store.js";

const databaseUrl = process.env.CONATUS_TEST_DATABASE_URL;

test("M1-05 serves a persistent account-scoped command center", { skip: !databaseUrl }, async (context) => {
  const store = new DomainStore(databaseUrl!);
  await store.migrate();
  const owner = await store.createAccount("Command Center Account", "Local Owner");
  const portfolio = await store.createPortfolio({
    accountId: owner.accountId,
    actorRef: `principal:${owner.principalId}`,
    idempotencyKey: `m1-05-${owner.accountId}`,
    workspaceName: "Conatus Workspace",
    productName: "Conatus",
    projectName: "Mac V1",
    taskName: "Command center",
    objective: "Navigate and resume work without paths",
  });
  await store.recordTaskResult({
    accountId: owner.accountId,
    taskId: portfolio.task.taskId,
    summary: "Read-only lifecycle verified",
    verificationState: "verified",
    actorRef: `principal:${owner.principalId}`,
  });
  const app = buildApp({
    commandCenter: {
      identityResolver: new LocalBearerIdentityResolver("disposable-token", owner),
      portfolioReader: store,
      now: () => new Date("2026-09-02T12:00:00.000Z"),
    },
  });
  context.after(async () => {
    await app.close();
    await store.close();
  });

  const response = await app.inject({
    method: "GET",
    url: "/v1/command-center",
    headers: { authorization: "Bearer disposable-token" },
  });
  assert.equal(response.statusCode, 200);
  assert.equal(isCommandCenterSnapshot(response.json()), true);
  assert.equal(response.json().products[0].projects[0].tasks[0].displayName, "Command center");
  for (const forbidden of [owner.accountId, "/Users/", "\"provider\"", "\"threadId\"", "\"cwd\"", "\"path\""]) {
    assert.equal(response.body.includes(forbidden), false, `payload exposed ${forbidden}`);
  }
});

// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import assert from "node:assert/strict";
import { test } from "node:test";
import { DomainNotFoundError, IdempotencyConflictError, StaleVersionError } from "../domain/errors.js";
import { DomainStore } from "./domain-store.js";

const databaseUrl = process.env.CONATUS_TEST_DATABASE_URL;

test("F02 durable kernel invariants", { skip: !databaseUrl }, async (context) => {
  const store = new DomainStore(databaseUrl!);
  await store.migrate();
  context.after(async () => store.close());

  const ownerA = await store.createAccount("Account A", "Owner A");
  const ownerB = await store.createAccount("Account B", "Owner B");
  const actorA = `principal:${ownerA.principalId}`;
  const actorB = `principal:${ownerB.principalId}`;
  const portfolioA = await store.createPortfolio({
    accountId: ownerA.accountId,
    actorRef: actorA,
    idempotencyKey: "portfolio-a",
    workspaceName: "Conatus Workspace",
    productName: "Conatus",
    projectName: "Mac V1",
    taskName: "Durable kernel",
    objective: "Prove durable account-scoped state",
  });

  await context.test("account scope hides reads and mutations", async () => {
    await assert.rejects(store.getTask(ownerB.accountId, portfolioA.task.taskId), DomainNotFoundError);
    await assert.rejects(
      store.renameTask({
        accountId: ownerB.accountId,
        taskId: portfolioA.task.taskId,
        actorRef: actorB,
        expectedVersion: 1,
        displayName: "Cross-account rename",
      }),
      DomainNotFoundError,
    );
    assert.equal((await store.getTask(ownerA.accountId, portfolioA.task.taskId)).displayName, "Durable kernel");
  });

  await context.test("scoped idempotency replays one command and rejects a changed request", async () => {
    const request = {
      accountId: ownerA.accountId,
      taskId: portfolioA.task.taskId,
      actorRef: actorA,
      idempotencyKey: "command-1",
      commandType: "task.message",
      payload: { text: "Continue F02" },
    };
    const first = await store.submitCommand(request);
    const replay = await store.submitCommand(request);
    assert.equal(replay.commandId, first.commandId);
    await assert.rejects(
      store.submitCommand({ ...request, payload: { text: "Different request" } }),
      IdempotencyConflictError,
    );
    const [execution, duplicate] = await Promise.all([
      store.beginExecution(ownerA.accountId, first.commandId, "service:test-gateway"),
      store.beginExecution(ownerA.accountId, first.commandId, "service:test-gateway"),
    ]);
    assert.deepEqual(duplicate, execution);
    await assert.rejects(
      store.beginExecution(ownerB.accountId, first.commandId, "service:test-gateway"),
      DomainNotFoundError,
    );
  });

  await context.test("one optimistic-version writer wins", async () => {
    const outcomes = await Promise.allSettled([
      store.renameTask({
        accountId: ownerA.accountId,
        taskId: portfolioA.task.taskId,
        actorRef: actorA,
        expectedVersion: 1,
        displayName: "Winner A",
      }),
      store.renameTask({
        accountId: ownerA.accountId,
        taskId: portfolioA.task.taskId,
        actorRef: actorA,
        expectedVersion: 1,
        displayName: "Winner B",
      }),
    ]);
    assert.equal(outcomes.filter((outcome) => outcome.status === "fulfilled").length, 1);
    const rejection = outcomes.find((outcome) => outcome.status === "rejected");
    assert.equal(rejection?.status === "rejected" && rejection.reason instanceof StaleVersionError, true);
    assert.equal((await store.getTask(ownerA.accountId, portfolioA.task.taskId)).version, 2);
  });

  await context.test("injected failure rolls aggregate, event, and outbox back together", async () => {
    const before = await store.evidence(ownerB.accountId);
    const failingStore = new DomainStore(databaseUrl!, {
      afterAggregateWrite: (aggregateType) => {
        if (aggregateType === "Portfolio") throw new Error("injected-before-event");
      },
    });
    context.after(async () => failingStore.close());
    await assert.rejects(
      failingStore.createPortfolio({
        accountId: ownerB.accountId,
        actorRef: actorB,
        idempotencyKey: "rollback-portfolio",
        workspaceName: "Rollback Workspace",
        productName: "Rollback Product",
        projectName: "Rollback Project",
        taskName: "Must not exist",
        objective: "Exercise rollback",
      }),
      /injected-before-event/,
    );
    const after = await store.evidence(ownerB.accountId);
    assert.deepEqual(after, before);
  });

  await context.test("events and outbox stay one-to-one and survive a fresh connection", async () => {
    const beforeRestart = await store.evidence(ownerA.accountId);
    assert.equal(beforeRestart.eventCount, beforeRestart.outboxCount);
    assert.equal(beforeRestart.pendingOutboxCount, beforeRestart.outboxCount);
    const restarted = new DomainStore(databaseUrl!);
    context.after(async () => restarted.close());
    const recoveredTask = await restarted.getTask(ownerA.accountId, portfolioA.task.taskId);
    assert.equal(recoveredTask.version, 2);
    assert.deepEqual(await restarted.evidence(ownerA.accountId), beforeRestart);
  });
});

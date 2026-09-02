// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  AmbiguousReferenceError,
  DomainNotFoundError,
  IdempotencyConflictError,
  InvalidReferenceError,
  StaleVersionError,
} from "../domain/errors.js";
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

test("M1-02 named portfolio projection", { skip: !databaseUrl }, async (context) => {
  const store = new DomainStore(databaseUrl!);
  await store.migrate();
  context.after(async () => store.close());

  const owner = await store.createAccount("Portfolio Account", "Portfolio Owner");
  const otherOwner = await store.createAccount("Other Portfolio Account", "Other Owner");
  const actorRef = `principal:${owner.principalId}`;
  const otherActorRef = `principal:${otherOwner.principalId}`;
  const conatus = await store.createPortfolio({
    accountId: owner.accountId,
    actorRef,
    idempotencyKey: "portfolio-conatus",
    workspaceName: "Conatus Workspace",
    productName: "Conatus",
    projectName: "Mac V1",
    taskName: "Voice review",
    objective: "Review the voice experience",
  });
  const kubo = await store.createPortfolio({
    accountId: owner.accountId,
    actorRef,
    idempotencyKey: "portfolio-kubo",
    workspaceName: "Kubo Workspace",
    productName: "Kubo",
    projectName: "Invoice Launch",
    taskName: "Invoice review",
    objective: "Review the invoice workflow",
  });

  await store.addPortfolioAlias({
    accountId: owner.accountId,
    entityType: "workspace",
    entityId: conatus.workspaceId,
    alias: "Main code",
    actorRef,
  });
  await Promise.all([
    store.addPortfolioAlias({
      accountId: owner.accountId,
      entityType: "product",
      entityId: conatus.productId,
      alias: "Jarvis",
      actorRef,
    }),
    store.addPortfolioAlias({
      accountId: owner.accountId,
      entityType: "product",
      entityId: conatus.productId,
      alias: "Jarvis",
      actorRef,
    }),
  ]);
  await store.addPortfolioAlias({
    accountId: owner.accountId,
    entityType: "project",
    entityId: conatus.projectId,
    alias: "Mac app",
    actorRef,
  });
  for (const task of [conatus.task, kubo.task]) {
    await store.addPortfolioAlias({
      accountId: owner.accountId,
      entityType: "task",
      entityId: task.taskId,
      alias: "Current review",
      actorRef,
    });
  }
  await store.addTaskBlocker({
    accountId: owner.accountId,
    taskId: conatus.task.taskId,
    summary: "Wake-word device validation is pending",
    actorRef,
  });
  await store.recordTaskResult({
    accountId: owner.accountId,
    taskId: conatus.task.taskId,
    summary: "Stable Codex contract verified locally",
    verificationState: "verified",
    actorRef,
  });
  for (let index = 1; index <= 5; index += 1) {
    await store.recordTaskResult({
      accountId: owner.accountId,
      taskId: conatus.task.taskId,
      summary: `Additional verified result ${index}`,
      verificationState: "verified",
      actorRef,
    });
  }

  await context.test("resolves IDs, primary names, and aliases without a path", async () => {
    assert.equal(
      (await store.resolvePortfolioReference({
        accountId: owner.accountId,
        entityType: "product",
        reference: "CÓNATUS!!!",
      })).entityId,
      conatus.productId,
    );
    assert.equal(
      (await store.resolvePortfolioReference({
        accountId: owner.accountId,
        entityType: "workspace",
        reference: "main CODE",
      })).entityId,
      conatus.workspaceId,
    );
    assert.equal(
      (await store.resolvePortfolioReference({
        accountId: owner.accountId,
        entityType: "project",
        reference: conatus.projectId,
      })).entityId,
      conatus.projectId,
    );
    await assert.rejects(
      store.resolvePortfolioReference({
        accountId: owner.accountId,
        entityType: "task",
        reference: "...",
      }),
      InvalidReferenceError,
    );
  });

  await context.test("returns deterministic ambiguity and accepts explicit project context", async () => {
    await assert.rejects(
      store.resolvePortfolioReference({
        accountId: owner.accountId,
        entityType: "task",
        reference: "current review",
      }),
      (error: unknown) => {
        assert.equal(error instanceof AmbiguousReferenceError, true);
        if (!(error instanceof AmbiguousReferenceError)) return false;
        assert.deepEqual(
          error.candidates.map((candidate) => candidate.displayName),
          ["Invoice review", "Voice review"],
        );
        assert.deepEqual(
          error.candidates.map((candidate) => candidate.parentDisplayName),
          ["Invoice Launch", "Mac V1"],
        );
        return true;
      },
    );
    const resolved = await store.resolvePortfolioReference({
      accountId: owner.accountId,
      entityType: "task",
      reference: "current review",
      parentId: conatus.projectId,
    });
    assert.equal(resolved.entityId, conatus.task.taskId);
  });

  await context.test("persists a path-free command-center projection across restart", async () => {
    const beforeRestart = await store.getPortfolioProjection(owner.accountId);
    assert.equal(beforeRestart.workspaces.length, 2);
    const conatusProduct = beforeRestart.products.find((product) => product.productId === conatus.productId)!;
    assert.deepEqual(conatusProduct.aliases, ["Jarvis"]);
    const conatusProject = conatusProduct.projects[0]!;
    assert.deepEqual(conatusProject.aliases, ["Mac app"]);
    const voiceTask = conatusProject.tasks[0]!;
    assert.deepEqual(voiceTask.aliases, ["Current review"]);
    assert.deepEqual(
      voiceTask.activeBlockers.map((blocker) => blocker.summary),
      ["Wake-word device validation is pending"],
    );
    assert.equal(voiceTask.recentResults.length, 5);
    assert.equal(voiceTask.recentResults.every((result) => result.verificationState === "verified"), true);
    const serialized = JSON.stringify(beforeRestart);
    for (const forbidden of ["/Users/", '"cwd"', '"path"', '"provider"', '"threadId"']) {
      assert.equal(serialized.includes(forbidden), false, `projection exposed ${forbidden}`);
    }

    const restarted = new DomainStore(databaseUrl!);
    context.after(async () => restarted.close());
    assert.deepEqual(await restarted.getPortfolioProjection(owner.accountId), beforeRestart);
  });

  await context.test("account scope hides aliases, projection state, and mutations", async () => {
    assert.deepEqual(await store.getPortfolioProjection(otherOwner.accountId), {
      accountId: otherOwner.accountId,
      workspaces: [],
      products: [],
    });
    await assert.rejects(
      store.resolvePortfolioReference({
        accountId: otherOwner.accountId,
        entityType: "product",
        reference: "Jarvis",
      }),
      DomainNotFoundError,
    );
    await assert.rejects(
      store.addPortfolioAlias({
        accountId: otherOwner.accountId,
        entityType: "task",
        entityId: conatus.task.taskId,
        alias: "Leaked task",
        actorRef: otherActorRef,
      }),
      DomainNotFoundError,
    );
    await assert.rejects(
      store.addTaskBlocker({
        accountId: otherOwner.accountId,
        taskId: conatus.task.taskId,
        summary: "Leaked blocker",
        actorRef: otherActorRef,
      }),
      DomainNotFoundError,
    );
  });

  await context.test("keeps durable events and outbox records one-to-one", async () => {
    const evidence = await store.evidence(owner.accountId);
    assert.equal(evidence.eventCount, evidence.outboxCount);
    assert.equal(evidence.pendingOutboxCount, evidence.outboxCount);
  });
});

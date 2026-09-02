// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { Pool, type PoolClient } from "pg";
import {
  AmbiguousReferenceError,
  DomainNotFoundError,
  IdempotencyConflictError,
  StaleVersionError,
} from "../domain/errors.js";
import { uuidV7 } from "../domain/ids.js";
import type {
  AccountOwner,
  CommandRecord,
  EvidenceSummary,
  ExecutionRecord,
  PortfolioEntityType,
  PortfolioProjection,
  PortfolioSeed,
  ResolvedPortfolioReference,
  TaskBlockerProjection,
  TaskRecord,
  TaskResultProjection,
} from "../domain/types.js";
import {
  aliasConfigurations,
  buildPortfolioProjection,
  mapReferenceCandidate,
  mapResolvedReference,
  normalizePortfolioReference,
  portfolioEntityTypes,
  requireSummary,
  type ReferenceRow,
} from "./portfolio-projection.js";

interface StoreOptions {
  afterAggregateWrite?: (aggregateType: string) => void;
}

interface EventInput {
  accountId: string;
  aggregateType: string;
  aggregateId: string;
  aggregateVersion: number;
  eventType: string;
  actorRef: string;
  correlationId: string;
  causationId?: string;
  payload: Record<string, unknown>;
}

type Queryable = Pick<PoolClient, "query">;

export class DomainStore {
  private readonly pool: Pool;

  constructor(connectionString: string, private readonly options: StoreOptions = {}) {
    this.pool = new Pool({ connectionString, max: 8 });
  }

  async close(): Promise<void> {
    await this.pool.end();
  }

  async migrate(): Promise<void> {
    const migrationsDirectory = new URL("../../migrations/", import.meta.url);
    const migrations = (await readdir(migrationsDirectory))
      .filter((entry) => /^\d+_[a-z0-9_]+\.sql$/.test(entry))
      .sort();
    const client = await this.pool.connect();
    let lockAcquired = false;
    try {
      await client.query("SELECT pg_advisory_lock(hashtext('conatus-schema-migrations'))");
      lockAcquired = true;
      await client.query(
        `CREATE TABLE IF NOT EXISTS schema_migrations (
           version integer PRIMARY KEY,
           applied_at timestamptz NOT NULL DEFAULT clock_timestamp()
         )`,
      );
      for (const migration of migrations) {
        const version = Number(migration.slice(0, migration.indexOf("_")));
        const applied = await client.query("SELECT 1 FROM schema_migrations WHERE version = $1", [version]);
        if (applied.rowCount) continue;
        await client.query(await readFile(new URL(migration, migrationsDirectory), "utf8"));
      }
    } finally {
      try {
        if (lockAcquired) {
          await client.query("SELECT pg_advisory_unlock(hashtext('conatus-schema-migrations'))");
        }
      } finally {
        client.release();
      }
    }
  }

  async createAccount(displayName: string, ownerDisplayName: string): Promise<AccountOwner> {
    const accountId = uuidV7();
    const principalId = uuidV7();
    const actorRef = `principal:${principalId}`;
    const correlationId = uuidV7();
    await this.transaction(async (client) => {
      const now = new Date();
      await client.query("SET CONSTRAINTS ALL DEFERRED");
      await client.query(
        `INSERT INTO accounts
          (account_id, display_name, state, owner_principal_id, version, created_at, updated_at, created_by, updated_by)
         VALUES ($1, $2, 'active', $3, 1, $4, $4, $5, $5)`,
        [accountId, displayName, principalId, now, actorRef],
      );
      await client.query(
        `INSERT INTO principals
          (account_id, principal_id, display_name, state, version, created_at, updated_at, created_by, updated_by)
         VALUES ($1, $2, $3, 'active', 1, $4, $4, $5, $5)`,
        [accountId, principalId, ownerDisplayName, now, actorRef],
      );
      await client.query("INSERT INTO account_sequences (account_id) VALUES ($1)", [accountId]);
      this.options.afterAggregateWrite?.("Account");
      await this.appendEvent(client, {
        accountId,
        aggregateType: "Account",
        aggregateId: accountId,
        aggregateVersion: 1,
        eventType: "AccountCreated",
        actorRef,
        correlationId,
        payload: { ownerPrincipalId: principalId },
      });
    });
    return { accountId, principalId };
  }

  async createPortfolio(input: {
    accountId: string;
    actorRef: string;
    idempotencyKey: string;
    workspaceName: string;
    productName: string;
    projectName: string;
    taskName: string;
    objective: string;
  }): Promise<PortfolioSeed> {
    const operationScope = "portfolio.create";
    const fingerprint = fingerprintRequest(input);
    return this.transaction(async (client) => {
      const existing = await this.reserveIdempotency(client, input.accountId, input.actorRef, operationScope, input.idempotencyKey, fingerprint);
      if (existing) return this.loadPortfolioByTask(client, input.accountId, existing);

      const workspaceId = uuidV7();
      const productId = uuidV7();
      const projectId = uuidV7();
      const taskId = uuidV7();
      const correlationId = uuidV7();
      const now = new Date();
      await client.query(
        `INSERT INTO workspaces
          (account_id, workspace_id, display_name, slug, state, version, created_at, updated_at, created_by, updated_by)
         VALUES ($1, $2, $3, $4, 'active', 1, $5, $5, $6, $6)`,
        [input.accountId, workspaceId, input.workspaceName, slugify(input.workspaceName), now, input.actorRef],
      );
      await client.query(
        `INSERT INTO products
          (account_id, product_id, display_name, slug, state, version, created_at, updated_at, created_by, updated_by)
         VALUES ($1, $2, $3, $4, 'active', 1, $5, $5, $6, $6)`,
        [input.accountId, productId, input.productName, slugify(input.productName), now, input.actorRef],
      );
      await client.query(
        `INSERT INTO projects
          (account_id, project_id, product_id, workspace_id, display_name, slug, state, version,
           created_at, updated_at, created_by, updated_by)
         VALUES ($1, $2, $3, $4, $5, $6, 'active', 1, $7, $7, $8, $8)`,
        [input.accountId, projectId, productId, workspaceId, input.projectName, slugify(input.projectName), now, input.actorRef],
      );
      await client.query(
        `INSERT INTO tasks
          (account_id, task_id, project_id, workspace_id, display_name, slug, objective, lifecycle_state,
           version, created_at, updated_at, created_by, updated_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'ready', 1, $8, $8, $9, $9)`,
        [input.accountId, taskId, projectId, workspaceId, input.taskName, slugify(input.taskName), input.objective, now, input.actorRef],
      );
      this.options.afterAggregateWrite?.("Portfolio");
      for (const event of [
        ["Workspace", workspaceId, "WorkspaceCreated"],
        ["Product", productId, "ProductCreated"],
        ["Project", projectId, "ProjectCreated"],
        ["Task", taskId, "TaskCreated"],
      ] as const) {
        await this.appendEvent(client, {
          accountId: input.accountId,
          aggregateType: event[0],
          aggregateId: event[1],
          aggregateVersion: 1,
          eventType: event[2],
          actorRef: input.actorRef,
          correlationId,
          payload: {},
        });
      }
      await this.resolveIdempotency(client, input.accountId, input.actorRef, operationScope, input.idempotencyKey, "Task", taskId);
      return { workspaceId, productId, projectId, task: await this.getTaskWith(client, input.accountId, taskId) };
    });
  }

  async getTask(accountId: string, taskId: string): Promise<TaskRecord> {
    return this.getTaskWith(this.pool, accountId, taskId);
  }

  async renameTask(input: {
    accountId: string;
    taskId: string;
    actorRef: string;
    expectedVersion: number;
    displayName: string;
  }): Promise<TaskRecord> {
    return this.transaction(async (client) => {
      const updated = await client.query(
        `UPDATE tasks SET display_name = $4, version = version + 1, updated_at = $5, updated_by = $3
         WHERE account_id = $1 AND task_id = $2 AND version = $6
         RETURNING *`,
        [input.accountId, input.taskId, input.actorRef, input.displayName, new Date(), input.expectedVersion],
      );
      if (updated.rowCount === 0) {
        const current = await client.query<{ version: string }>(
          "SELECT version FROM tasks WHERE account_id = $1 AND task_id = $2",
          [input.accountId, input.taskId],
        );
        if (current.rowCount === 0) throw new DomainNotFoundError("Task");
        throw new StaleVersionError(Number(current.rows[0]!.version));
      }
      const row = updated.rows[0]!;
      this.options.afterAggregateWrite?.("Task");
      await this.appendEvent(client, {
        accountId: input.accountId,
        aggregateType: "Task",
        aggregateId: input.taskId,
        aggregateVersion: Number(row.version),
        eventType: "TaskRenamed",
        actorRef: input.actorRef,
        correlationId: uuidV7(),
        payload: { displayName: input.displayName },
      });
      return mapTask(row);
    });
  }

  async addPortfolioAlias(input: {
    accountId: string;
    entityType: PortfolioEntityType;
    entityId: string;
    alias: string;
    actorRef: string;
  }): Promise<void> {
    const normalizedAlias = normalizePortfolioReference(input.alias);
    const config = aliasConfigurations[input.entityType];
    await this.transaction(async (client) => {
      const target = await client.query(
        `SELECT 1 FROM ${config.entityTable}
         WHERE account_id = $1 AND ${config.idColumn} = $2 FOR UPDATE`,
        [input.accountId, input.entityId],
      );
      if (!target.rowCount) throw new DomainNotFoundError(config.aggregateType);
      const existing = await client.query(
        `SELECT 1 FROM ${config.aliasTable}
         WHERE account_id = $1 AND ${config.idColumn} = $2 AND normalized_alias = $3`,
        [input.accountId, input.entityId, normalizedAlias],
      );
      if (existing.rowCount) return;

      const updated = await client.query<{ version: string }>(
        `UPDATE ${config.entityTable}
         SET version = version + 1, updated_at = $3, updated_by = $4
         WHERE account_id = $1 AND ${config.idColumn} = $2
         RETURNING version`,
        [input.accountId, input.entityId, new Date(), input.actorRef],
      );
      const now = new Date();
      await client.query(
        `INSERT INTO ${config.aliasTable}
          (account_id, ${config.idColumn}, alias, normalized_alias, created_at, created_by)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [input.accountId, input.entityId, input.alias.trim(), normalizedAlias, now, input.actorRef],
      );
      this.options.afterAggregateWrite?.(config.aggregateType);
      await this.appendEvent(client, {
        accountId: input.accountId,
        aggregateType: config.aggregateType,
        aggregateId: input.entityId,
        aggregateVersion: Number(updated.rows[0]!.version),
        eventType: `${config.aggregateType}AliasAdded`,
        actorRef: input.actorRef,
        correlationId: uuidV7(),
        payload: { alias: input.alias.trim(), normalizedAlias },
      });
    });
  }

  async addTaskBlocker(input: {
    accountId: string;
    taskId: string;
    summary: string;
    actorRef: string;
  }): Promise<TaskBlockerProjection> {
    const summary = requireSummary(input.summary);
    return this.transaction(async (client) => {
      const now = new Date();
      const task = await client.query<{ version: string }>(
        `UPDATE tasks SET version = version + 1, updated_at = $3, updated_by = $4
         WHERE account_id = $1 AND task_id = $2 RETURNING version`,
        [input.accountId, input.taskId, now, input.actorRef],
      );
      if (!task.rowCount) throw new DomainNotFoundError("Task");
      const blockerId = uuidV7();
      await client.query(
        `INSERT INTO task_blockers
          (account_id, blocker_id, task_id, summary, state, created_at, created_by)
         VALUES ($1, $2, $3, $4, 'active', $5, $6)`,
        [input.accountId, blockerId, input.taskId, summary, now, input.actorRef],
      );
      this.options.afterAggregateWrite?.("Task");
      await this.appendEvent(client, {
        accountId: input.accountId,
        aggregateType: "Task",
        aggregateId: input.taskId,
        aggregateVersion: Number(task.rows[0]!.version),
        eventType: "TaskBlockerAdded",
        actorRef: input.actorRef,
        correlationId: uuidV7(),
        payload: { blockerId, summary },
      });
      return { blockerId, summary, createdAt: now.toISOString() };
    });
  }

  async recordTaskResult(input: {
    accountId: string;
    taskId: string;
    summary: string;
    verificationState: "unverified" | "verified" | "failed";
    actorRef: string;
  }): Promise<TaskResultProjection> {
    const summary = requireSummary(input.summary);
    return this.transaction(async (client) => {
      const now = new Date();
      const task = await client.query<{ version: string }>(
        `UPDATE tasks SET version = version + 1, updated_at = $3, updated_by = $4
         WHERE account_id = $1 AND task_id = $2 RETURNING version`,
        [input.accountId, input.taskId, now, input.actorRef],
      );
      if (!task.rowCount) throw new DomainNotFoundError("Task");
      const resultId = uuidV7();
      await client.query(
        `INSERT INTO task_results
          (account_id, result_id, task_id, summary, verification_state, recorded_at, recorded_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [input.accountId, resultId, input.taskId, summary, input.verificationState, now, input.actorRef],
      );
      this.options.afterAggregateWrite?.("Task");
      await this.appendEvent(client, {
        accountId: input.accountId,
        aggregateType: "Task",
        aggregateId: input.taskId,
        aggregateVersion: Number(task.rows[0]!.version),
        eventType: "TaskResultRecorded",
        actorRef: input.actorRef,
        correlationId: uuidV7(),
        payload: { resultId, summary, verificationState: input.verificationState },
      });
      return {
        resultId,
        summary,
        verificationState: input.verificationState,
        recordedAt: now.toISOString(),
      };
    });
  }

  async resolvePortfolioReference(input: {
    accountId: string;
    entityType: PortfolioEntityType;
    reference: string;
    parentId?: string;
  }): Promise<ResolvedPortfolioReference> {
    const normalizedReference = normalizePortfolioReference(input.reference);
    const config = aliasConfigurations[input.entityType];
    const parentJoin = config.parentTable
      ? `LEFT JOIN ${config.parentTable} parent
           ON parent.account_id = entity.account_id AND parent.${config.parentIdColumn} = entity.${config.parentColumn}`
      : "";
    const parentSelect = config.parentTable
      ? `entity.${config.parentColumn} AS parent_id, parent.display_name AS parent_display_name`
      : "NULL::uuid AS parent_id, NULL::text AS parent_display_name";
    const parentFilter = input.parentId && config.parentColumn
      ? `AND entity.${config.parentColumn} = $4`
      : "";
    const parameters = input.parentId && config.parentColumn
      ? [input.accountId, input.reference.trim().toLowerCase(), normalizedReference, input.parentId]
      : [input.accountId, input.reference.trim().toLowerCase(), normalizedReference];
    const matches = await this.pool.query<ReferenceRow>(
      `SELECT entity.${config.idColumn} AS entity_id, entity.display_name, entity.slug,
         ${parentSelect}
       FROM ${config.entityTable} entity
       ${parentJoin}
       WHERE entity.account_id = $1
         AND (
           entity.${config.idColumn}::text = $2
           OR entity.slug = $3
           OR EXISTS (
             SELECT 1 FROM ${config.aliasTable} alias
             WHERE alias.account_id = entity.account_id
               AND alias.${config.idColumn} = entity.${config.idColumn}
               AND alias.normalized_alias = $3
           )
         )
         ${parentFilter}
       ORDER BY lower(entity.display_name), entity.${config.idColumn}`,
      parameters,
    );
    if (!matches.rowCount) throw new DomainNotFoundError(config.aggregateType);
    if (matches.rowCount > 1) {
      throw new AmbiguousReferenceError(
        input.entityType,
        input.reference,
        matches.rows.map(mapReferenceCandidate),
      );
    }
    return mapResolvedReference(input.entityType, matches.rows[0]!);
  }

  async getPortfolioProjection(accountId: string): Promise<PortfolioProjection> {
    return this.transaction(async (client) => {
      await client.query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY");
      const workspaces = await client.query(
        `SELECT workspace_id, display_name, slug, state FROM workspaces
         WHERE account_id = $1 ORDER BY lower(display_name), workspace_id`,
        [accountId],
      );
      const products = await client.query(
        `SELECT product_id, display_name, slug, state, version FROM products
         WHERE account_id = $1 ORDER BY lower(display_name), product_id`,
        [accountId],
      );
      const projects = await client.query(
        `SELECT project_id, product_id, workspace_id, display_name, slug, state, version FROM projects
         WHERE account_id = $1 ORDER BY lower(display_name), project_id`,
        [accountId],
      );
      const tasks = await client.query(
        `SELECT task_id, project_id, workspace_id, display_name, slug, objective, lifecycle_state, version
         FROM tasks WHERE account_id = $1 ORDER BY lower(display_name), task_id`,
        [accountId],
      );
      const blockers = await client.query(
        `SELECT blocker_id, task_id, summary, created_at FROM task_blockers
         WHERE account_id = $1 AND state = 'active'
         ORDER BY created_at, blocker_id`,
        [accountId],
      );
      const results = await client.query(
        `SELECT result_id, task_id, summary, verification_state, recorded_at
         FROM (
           SELECT result_id, task_id, summary, verification_state, recorded_at,
             row_number() OVER (PARTITION BY task_id ORDER BY recorded_at DESC, result_id DESC) AS result_rank
           FROM task_results WHERE account_id = $1
         ) ranked
         WHERE result_rank <= 5
         ORDER BY task_id, recorded_at DESC, result_id DESC`,
        [accountId],
      );
      const aliasRows = {} as Record<PortfolioEntityType, Record<string, unknown>[]>;
      for (const entityType of portfolioEntityTypes) {
        const config = aliasConfigurations[entityType];
        const rows = await client.query(
          `SELECT ${config.idColumn} AS entity_id, alias FROM ${config.aliasTable}
           WHERE account_id = $1 ORDER BY lower(alias), alias`,
          [accountId],
        );
        aliasRows[entityType] = rows.rows;
      }
      return buildPortfolioProjection({
        accountId,
        workspaceRows: workspaces.rows,
        productRows: products.rows,
        projectRows: projects.rows,
        taskRows: tasks.rows,
        blockerRows: blockers.rows,
        resultRows: results.rows,
        aliasRows,
      });
    });
  }

  async submitCommand(input: {
    accountId: string;
    taskId: string;
    actorRef: string;
    idempotencyKey: string;
    commandType: string;
    payload: Record<string, unknown>;
  }): Promise<CommandRecord> {
    const operationScope = "command.submit";
    const fingerprint = fingerprintRequest({ taskId: input.taskId, commandType: input.commandType, payload: input.payload });
    return this.transaction(async (client) => {
      const existing = await this.reserveIdempotency(client, input.accountId, input.actorRef, operationScope, input.idempotencyKey, fingerprint);
      if (existing) return this.getCommandWith(client, input.accountId, existing);
      await this.getTaskWith(client, input.accountId, input.taskId);
      const commandId = uuidV7();
      const correlationId = uuidV7();
      const now = new Date();
      await client.query(
        `INSERT INTO commands
          (account_id, command_id, task_id, actor_ref, operation_scope, idempotency_key, request_fingerprint,
           command_type, payload, state, correlation_id, version, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'accepted', $10, 1, $11, $11)`,
        [input.accountId, commandId, input.taskId, input.actorRef, operationScope, input.idempotencyKey, fingerprint, input.commandType, input.payload, correlationId, now],
      );
      this.options.afterAggregateWrite?.("Command");
      await this.appendEvent(client, {
        accountId: input.accountId,
        aggregateType: "Command",
        aggregateId: commandId,
        aggregateVersion: 1,
        eventType: "CommandAccepted",
        actorRef: input.actorRef,
        correlationId,
        payload: { taskId: input.taskId, commandType: input.commandType },
      });
      await this.resolveIdempotency(client, input.accountId, input.actorRef, operationScope, input.idempotencyKey, "Command", commandId);
      return this.getCommandWith(client, input.accountId, commandId);
    });
  }

  async beginExecution(accountId: string, commandId: string, actorRef: string): Promise<ExecutionRecord> {
    try {
      return await this.transaction(async (client) => {
        const existing = await this.loadExecution(client, accountId, commandId);
        if (existing) return existing;
        const command = await this.getCommandWith(client, accountId, commandId);
        const deliveryId = uuidV7();
        const executionAttemptId = uuidV7();
        const now = new Date();
        await client.query(
          `INSERT INTO deliveries
            (account_id, delivery_id, command_id, destination_type, state, attempt_count, actor_ref,
             correlation_id, causation_id, version, created_at, updated_at)
           VALUES ($1, $2, $3, 'mac_gateway', 'acknowledged', 1, $4, $5, $3, 1, $6, $6)`,
          [accountId, deliveryId, commandId, actorRef, command.correlationId, now],
        );
        await client.query(
          `INSERT INTO execution_attempts
            (account_id, execution_attempt_id, command_id, delivery_id, executor_type, state, actor_ref,
             correlation_id, causation_id, version, created_at, updated_at)
           VALUES ($1, $2, $3, $4, 'codex_gateway', 'accepted', $5, $6, $4, 1, $7, $7)`,
          [accountId, executionAttemptId, commandId, deliveryId, actorRef, command.correlationId, now],
        );
        this.options.afterAggregateWrite?.("ExecutionAttempt");
        await this.appendEvent(client, {
          accountId,
          aggregateType: "Delivery",
          aggregateId: deliveryId,
          aggregateVersion: 1,
          eventType: "DeliveryAcknowledged",
          actorRef,
          correlationId: command.correlationId,
          causationId: commandId,
          payload: { commandId },
        });
        await this.appendEvent(client, {
          accountId,
          aggregateType: "ExecutionAttempt",
          aggregateId: executionAttemptId,
          aggregateVersion: 1,
          eventType: "ExecutionAttemptAccepted",
          actorRef,
          correlationId: command.correlationId,
          causationId: deliveryId,
          payload: { commandId, deliveryId },
        });
        return { deliveryId, executionAttemptId };
      });
    } catch (error) {
      if (!isUniqueViolation(error)) throw error;
      const existing = await this.loadExecution(this.pool, accountId, commandId);
      if (!existing) throw error;
      return existing;
    }
  }

  async evidence(accountId: string): Promise<EvidenceSummary> {
    const result = await this.pool.query<{ event_count: string; outbox_count: string; pending_count: string }>(
      `SELECT
         (SELECT count(*) FROM domain_events WHERE account_id = $1) AS event_count,
         (SELECT count(*) FROM outbox_records WHERE account_id = $1) AS outbox_count,
         (SELECT count(*) FROM outbox_records WHERE account_id = $1 AND state = 'pending') AS pending_count`,
      [accountId],
    );
    const row = result.rows[0]!;
    return { eventCount: Number(row.event_count), outboxCount: Number(row.outbox_count), pendingOutboxCount: Number(row.pending_count) };
  }

  private async transaction<T>(work: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const result = await work(client);
      await client.query("COMMIT");
      return result;
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  private async appendEvent(client: PoolClient, input: EventInput): Promise<void> {
    const position = await client.query<{ next_position: string }>(
      "UPDATE account_sequences SET next_position = next_position + 1 WHERE account_id = $1 RETURNING next_position",
      [input.accountId],
    );
    if (!position.rowCount) throw new DomainNotFoundError("Account sequence");
    const eventId = uuidV7();
    const recordedAt = new Date();
    await client.query(
      `INSERT INTO domain_events
        (account_id, event_id, account_position, aggregate_type, aggregate_id, aggregate_version, event_type,
         schema_version, actor_ref, correlation_id, causation_id, recorded_at, payload)
       VALUES ($1, $2, $3, $4, $5, $6, $7, 1, $8, $9, $10, $11, $12)`,
      [input.accountId, eventId, position.rows[0]!.next_position, input.aggregateType, input.aggregateId,
        input.aggregateVersion, input.eventType, input.actorRef, input.correlationId, input.causationId ?? null,
        recordedAt, input.payload],
    );
    await client.query(
      `INSERT INTO outbox_records
        (account_id, outbox_record_id, event_id, topic, payload, state, created_at)
       VALUES ($1, $2, $3, $4, $5, 'pending', $6)`,
      [input.accountId, uuidV7(), eventId, `domain.${input.eventType}`, input.payload, recordedAt],
    );
  }

  private async reserveIdempotency(
    client: PoolClient,
    accountId: string,
    actorRef: string,
    operationScope: string,
    idempotencyKey: string,
    fingerprint: string,
  ): Promise<string | undefined> {
    const inserted = await client.query(
      `INSERT INTO idempotency_records
        (account_id, actor_ref, operation_scope, idempotency_key, request_fingerprint, state, first_accepted_at, expires_at)
       VALUES ($1, $2, $3, $4, $5, 'in_progress', $6, $7)
       ON CONFLICT DO NOTHING RETURNING idempotency_key`,
      [accountId, actorRef, operationScope, idempotencyKey, fingerprint, new Date(), new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)],
    );
    if (inserted.rowCount) return undefined;
    const existing = await client.query<{ request_fingerprint: string; canonical_entity_id: string | null; state: string }>(
      `SELECT request_fingerprint, canonical_entity_id, state FROM idempotency_records
       WHERE account_id = $1 AND actor_ref = $2 AND operation_scope = $3 AND idempotency_key = $4`,
      [accountId, actorRef, operationScope, idempotencyKey],
    );
    const row = existing.rows[0];
    if (!row || row.request_fingerprint !== fingerprint) throw new IdempotencyConflictError();
    if (row.state !== "resolved" || !row.canonical_entity_id) throw new Error("Idempotent operation is still in progress");
    return row.canonical_entity_id;
  }

  private async resolveIdempotency(
    client: PoolClient,
    accountId: string,
    actorRef: string,
    operationScope: string,
    idempotencyKey: string,
    entityType: string,
    entityId: string,
  ): Promise<void> {
    await client.query(
      `UPDATE idempotency_records SET state = 'resolved', canonical_entity_type = $5, canonical_entity_id = $6
       WHERE account_id = $1 AND actor_ref = $2 AND operation_scope = $3 AND idempotency_key = $4`,
      [accountId, actorRef, operationScope, idempotencyKey, entityType, entityId],
    );
  }

  private async getTaskWith(client: Queryable, accountId: string, taskId: string): Promise<TaskRecord> {
    const result = await client.query("SELECT * FROM tasks WHERE account_id = $1 AND task_id = $2", [accountId, taskId]);
    if (!result.rowCount) throw new DomainNotFoundError("Task");
    return mapTask(result.rows[0]!);
  }

  private async getCommandWith(client: Queryable, accountId: string, commandId: string): Promise<CommandRecord> {
    const result = await client.query("SELECT * FROM commands WHERE account_id = $1 AND command_id = $2", [accountId, commandId]);
    if (!result.rowCount) throw new DomainNotFoundError("Command");
    const row = result.rows[0]!;
    return {
      accountId: row.account_id,
      commandId: row.command_id,
      taskId: row.task_id,
      actorRef: row.actor_ref,
      requestFingerprint: row.request_fingerprint,
      state: row.state,
      correlationId: row.correlation_id,
    };
  }

  private async loadPortfolioByTask(client: Queryable, accountId: string, taskId: string): Promise<PortfolioSeed> {
    const task = await this.getTaskWith(client, accountId, taskId);
    const result = await client.query(
      `SELECT p.product_id FROM projects p WHERE p.account_id = $1 AND p.project_id = $2`,
      [accountId, task.projectId],
    );
    return { workspaceId: task.workspaceId, productId: result.rows[0]!.product_id, projectId: task.projectId, task };
  }

  private async loadExecution(client: Queryable, accountId: string, commandId: string): Promise<ExecutionRecord | undefined> {
    const existing = await client.query<{ delivery_id: string; execution_attempt_id: string }>(
      `SELECT d.delivery_id, e.execution_attempt_id
       FROM deliveries d JOIN execution_attempts e
         ON e.account_id = d.account_id AND e.delivery_id = d.delivery_id
       WHERE d.account_id = $1 AND d.command_id = $2`,
      [accountId, commandId],
    );
    return existing.rowCount ? mapExecution(existing.rows[0]!) : undefined;
  }
}

export function fingerprintRequest(value: unknown): string {
  return createHash("sha256").update(canonicalJson(value)).digest("hex");
}

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>).sort(([left], [right]) => left.localeCompare(right));
    return `{${entries.map(([key, item]) => `${JSON.stringify(key)}:${canonicalJson(item)}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function slugify(value: string): string {
  return normalizePortfolioReference(value);
}

function mapTask(row: Record<string, unknown>): TaskRecord {
  return {
    accountId: String(row.account_id),
    taskId: String(row.task_id),
    projectId: String(row.project_id),
    workspaceId: String(row.workspace_id),
    displayName: String(row.display_name),
    slug: String(row.slug),
    objective: String(row.objective),
    lifecycleState: String(row.lifecycle_state),
    version: Number(row.version),
  };
}

function mapExecution(row: { delivery_id: string; execution_attempt_id: string }): ExecutionRecord {
  return { deliveryId: row.delivery_id, executionAttemptId: row.execution_attempt_id };
}

function isUniqueViolation(error: unknown): boolean {
  return typeof error === "object" && error !== null && "code" in error && error.code === "23505";
}

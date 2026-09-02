// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { InvalidReferenceError, InvalidSummaryError, type ReferenceCandidate } from "../domain/errors.js";
import type {
  PortfolioEntityType,
  PortfolioProjection,
  ProductProjection,
  ProjectProjection,
  ResolvedPortfolioReference,
  TaskBlockerProjection,
  TaskProjection,
  TaskResultProjection,
  WorkspaceProjection,
} from "../domain/types.js";

interface AliasConfiguration {
  entityTable: string;
  aliasTable: string;
  idColumn: string;
  aggregateType: string;
  parentColumn?: string;
  parentTable?: string;
  parentIdColumn?: string;
}

export interface ReferenceRow {
  entity_id: string;
  display_name: string;
  slug: string;
  parent_id: string | null;
  parent_display_name: string | null;
}

export const portfolioEntityTypes: readonly PortfolioEntityType[] = ["workspace", "product", "project", "task"];

export const aliasConfigurations: Record<PortfolioEntityType, AliasConfiguration> = {
  workspace: {
    entityTable: "workspaces",
    aliasTable: "workspace_aliases",
    idColumn: "workspace_id",
    aggregateType: "Workspace",
  },
  product: {
    entityTable: "products",
    aliasTable: "product_aliases",
    idColumn: "product_id",
    aggregateType: "Product",
  },
  project: {
    entityTable: "projects",
    aliasTable: "project_aliases",
    idColumn: "project_id",
    aggregateType: "Project",
    parentColumn: "product_id",
    parentTable: "products",
    parentIdColumn: "product_id",
  },
  task: {
    entityTable: "tasks",
    aliasTable: "task_aliases",
    idColumn: "task_id",
    aggregateType: "Task",
    parentColumn: "project_id",
    parentTable: "projects",
    parentIdColumn: "project_id",
  },
};

export function normalizePortfolioReference(value: string): string {
  const normalized = value
    .trim()
    .toLowerCase()
    .normalize("NFKD")
    .replace(/\p{Mark}/gu, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
  if (!normalized) throw new InvalidReferenceError();
  return normalized;
}

export function requireSummary(value: string): string {
  const summary = value.trim();
  if (!summary) throw new InvalidSummaryError();
  return summary;
}

export function mapReferenceCandidate(row: ReferenceRow): ReferenceCandidate {
  return {
    entityId: row.entity_id,
    displayName: row.display_name,
    slug: row.slug,
    ...(row.parent_id ? { parentId: row.parent_id } : {}),
    ...(row.parent_display_name ? { parentDisplayName: row.parent_display_name } : {}),
  };
}

export function mapResolvedReference(
  entityType: PortfolioEntityType,
  row: ReferenceRow,
): ResolvedPortfolioReference {
  return { entityType, ...mapReferenceCandidate(row) };
}

export function buildPortfolioProjection(input: {
  accountId: string;
  workspaceRows: Record<string, unknown>[];
  productRows: Record<string, unknown>[];
  projectRows: Record<string, unknown>[];
  taskRows: Record<string, unknown>[];
  blockerRows: Record<string, unknown>[];
  resultRows: Record<string, unknown>[];
  aliasRows: Record<PortfolioEntityType, Record<string, unknown>[]>;
}): PortfolioProjection {
  const aliases = Object.fromEntries(
    portfolioEntityTypes.map((entityType) => [entityType, groupStrings(input.aliasRows[entityType], "entity_id", "alias")]),
  ) as Record<PortfolioEntityType, Map<string, string[]>>;
  const blockersByTask = groupMapped(input.blockerRows, "task_id", (row): TaskBlockerProjection => ({
    blockerId: String(row.blocker_id),
    summary: String(row.summary),
    createdAt: isoTimestamp(row.created_at),
  }));
  const resultsByTask = groupMapped(input.resultRows, "task_id", (row): TaskResultProjection => ({
    resultId: String(row.result_id),
    summary: String(row.summary),
    verificationState: String(row.verification_state),
    recordedAt: isoTimestamp(row.recorded_at),
  }));
  const tasksByProject = groupMapped(input.taskRows, "project_id", (row): TaskProjection => {
    const taskId = String(row.task_id);
    return {
      taskId,
      workspaceId: String(row.workspace_id),
      displayName: String(row.display_name),
      slug: String(row.slug),
      objective: String(row.objective),
      lifecycleState: String(row.lifecycle_state),
      version: Number(row.version),
      aliases: aliases.task.get(taskId) ?? [],
      activeBlockers: blockersByTask.get(taskId) ?? [],
      recentResults: resultsByTask.get(taskId) ?? [],
    };
  });
  const projectsByProduct = groupMapped(input.projectRows, "product_id", (row): ProjectProjection => {
    const projectId = String(row.project_id);
    return {
      projectId,
      workspaceId: String(row.workspace_id),
      displayName: String(row.display_name),
      slug: String(row.slug),
      state: String(row.state),
      version: Number(row.version),
      aliases: aliases.project.get(projectId) ?? [],
      tasks: tasksByProject.get(projectId) ?? [],
    };
  });
  const workspaces: WorkspaceProjection[] = input.workspaceRows.map((row) => {
    const workspaceId = String(row.workspace_id);
    return {
      workspaceId,
      displayName: String(row.display_name),
      handle: String(row.slug),
      state: String(row.state),
      aliases: aliases.workspace.get(workspaceId) ?? [],
    };
  });
  const products: ProductProjection[] = input.productRows.map((row) => {
    const productId = String(row.product_id);
    return {
      productId,
      displayName: String(row.display_name),
      slug: String(row.slug),
      state: String(row.state),
      version: Number(row.version),
      aliases: aliases.product.get(productId) ?? [],
      projects: projectsByProduct.get(productId) ?? [],
    };
  });
  return { accountId: input.accountId, workspaces, products };
}

function groupStrings(
  rows: Record<string, unknown>[],
  keyColumn: string,
  valueColumn: string,
): Map<string, string[]> {
  return groupMapped(rows, keyColumn, (row) => String(row[valueColumn]));
}

function groupMapped<T>(
  rows: Record<string, unknown>[],
  keyColumn: string,
  map: (row: Record<string, unknown>) => T,
): Map<string, T[]> {
  const grouped = new Map<string, T[]>();
  for (const row of rows) {
    const key = String(row[keyColumn]);
    const values = grouped.get(key) ?? [];
    values.push(map(row));
    grouped.set(key, values);
  }
  return grouped;
}

function isoTimestamp(value: unknown): string {
  if (value instanceof Date) return value.toISOString();
  return new Date(String(value)).toISOString();
}

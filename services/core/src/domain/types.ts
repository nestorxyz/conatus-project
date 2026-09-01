// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

export interface AccountOwner {
  accountId: string;
  principalId: string;
}

export interface PortfolioSeed {
  workspaceId: string;
  productId: string;
  projectId: string;
  task: TaskRecord;
}

export interface TaskRecord {
  accountId: string;
  taskId: string;
  projectId: string;
  workspaceId: string;
  displayName: string;
  slug: string;
  objective: string;
  lifecycleState: string;
  version: number;
}

export interface CommandRecord {
  accountId: string;
  commandId: string;
  taskId: string;
  actorRef: string;
  requestFingerprint: string;
  state: string;
  correlationId: string;
}

export interface ExecutionRecord {
  deliveryId: string;
  executionAttemptId: string;
}

export interface EvidenceSummary {
  eventCount: number;
  outboxCount: number;
  pendingOutboxCount: number;
}

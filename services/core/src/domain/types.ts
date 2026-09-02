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

export interface IssuedVoiceGrant {
  schemaVersion: 1;
  voiceGrantId: string;
  relayToken: string;
  scope: "transcribe_post_wake_audio";
  issuedAt: string;
  expiresAt: string;
  maxAudioMilliseconds: number;
  maxTurns: number;
}

export interface VoiceGrantUsage {
  voiceGrantId: string;
  state: "active" | "exhausted";
  remainingAudioMilliseconds: number;
  remainingTurns: number;
}

export interface VoiceQuotaEvidence {
  activeGrantCount: number;
  consumedAudioMilliseconds: number;
  reservedAudioMilliseconds: number;
}

export type PortfolioEntityType = "workspace" | "product" | "project" | "task";

export interface ResolvedPortfolioReference {
  entityType: PortfolioEntityType;
  entityId: string;
  displayName: string;
  slug: string;
  parentId?: string;
  parentDisplayName?: string;
}

export interface WorkspaceProjection {
  workspaceId: string;
  displayName: string;
  handle: string;
  state: string;
  aliases: string[];
}

export interface TaskBlockerProjection {
  blockerId: string;
  summary: string;
  createdAt: string;
}

export interface TaskResultProjection {
  resultId: string;
  summary: string;
  verificationState: string;
  recordedAt: string;
}

export interface TaskProjection {
  taskId: string;
  workspaceId: string;
  displayName: string;
  slug: string;
  objective: string;
  lifecycleState: string;
  version: number;
  aliases: string[];
  activeBlockers: TaskBlockerProjection[];
  recentResults: TaskResultProjection[];
}

export interface ProjectProjection {
  projectId: string;
  workspaceId: string;
  displayName: string;
  slug: string;
  state: string;
  version: number;
  aliases: string[];
  tasks: TaskProjection[];
}

export interface ProductProjection {
  productId: string;
  displayName: string;
  slug: string;
  state: string;
  version: number;
  aliases: string[];
  projects: ProjectProjection[];
}

export interface PortfolioProjection {
  accountId: string;
  workspaces: WorkspaceProjection[];
  products: ProductProjection[];
}

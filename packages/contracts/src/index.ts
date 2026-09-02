// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

export interface ComponentHealth {
  schemaVersion: 1;
  component: "core" | "mac";
  state: "ready" | "degraded";
  version: string;
}

export function isComponentHealth(value: unknown): value is ComponentHealth {
  if (typeof value !== "object" || value === null) return false;
  const candidate = value as Record<string, unknown>;
  return candidate.schemaVersion === 1
    && (candidate.component === "core" || candidate.component === "mac")
    && (candidate.state === "ready" || candidate.state === "degraded")
    && typeof candidate.version === "string"
    && candidate.version.length > 0;
}

export const voiceLifecycleStates = [
  "off",
  "armed",
  "acknowledging",
  "capturing",
  "transcribing",
  "routing",
  "working",
  "speaking",
  "recovering",
  "blocked",
] as const;

export type VoiceLifecycleState = typeof voiceLifecycleStates[number];
export type VoiceConversationMode = "wake_required" | "follow_up";

export interface VoiceStatusSnapshot {
  schemaVersion: 1;
  state: VoiceLifecycleState;
  conversationMode: VoiceConversationMode;
  recoverable: boolean;
}

export function isVoiceStatusSnapshot(value: unknown): value is VoiceStatusSnapshot {
  if (!isRecord(value) || containsForbiddenKey(value)) return false;
  const shapeIsValid = hasExactKeys(value, ["schemaVersion", "state", "conversationMode", "recoverable"])
    && value.schemaVersion === 1
    && voiceLifecycleStates.some((state) => state === value.state)
    && (value.conversationMode === "wake_required" || value.conversationMode === "follow_up")
    && typeof value.recoverable === "boolean";
  if (!shapeIsValid) return false;
  if ((value.state === "off" || value.state === "armed") && value.conversationMode !== "wake_required") return false;
  if (value.state === "recovering") return value.recoverable === true;
  if (value.state === "blocked") return true;
  return value.recoverable === false;
}

export interface VoiceGrantRequest {
  schemaVersion: 1;
  requestedAudioMilliseconds: number;
  requestedTurns: number;
}

export interface VoiceGrantResponse {
  schemaVersion: 1;
  voiceGrantId: string;
  relayToken: string;
  scope: "transcribe_post_wake_audio";
  issuedAt: string;
  expiresAt: string;
  maxAudioMilliseconds: number;
  maxTurns: number;
}

export function isVoiceGrantRequest(value: unknown): value is VoiceGrantRequest {
  return isRecord(value)
    && hasExactKeys(value, ["schemaVersion", "requestedAudioMilliseconds", "requestedTurns"])
    && value.schemaVersion === 1
    && isIntegerBetween(value.requestedAudioMilliseconds, 1_000, 300_000)
    && isIntegerBetween(value.requestedTurns, 1, 10);
}

export function isVoiceGrantResponse(value: unknown): value is VoiceGrantResponse {
  if (!isRecord(value)) return false;
  return hasExactKeys(value, [
    "schemaVersion", "voiceGrantId", "relayToken", "scope", "issuedAt", "expiresAt",
    "maxAudioMilliseconds", "maxTurns",
  ])
    && value.schemaVersion === 1
    && typeof value.voiceGrantId === "string"
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value.voiceGrantId)
    && typeof value.relayToken === "string"
    && /^[A-Za-z0-9_-]{43}$/.test(value.relayToken)
    && value.scope === "transcribe_post_wake_audio"
    && isTimestamp(value.issuedAt)
    && isTimestamp(value.expiresAt)
    && Date.parse(value.expiresAt) > Date.parse(value.issuedAt)
    && isIntegerBetween(value.maxAudioMilliseconds, 1_000, 300_000)
    && isIntegerBetween(value.maxTurns, 1, 10);
}

export interface CommandCenterSnapshot {
  schemaVersion: 1;
  observedAt: string;
  workspaces: CommandCenterWorkspace[];
  products: CommandCenterProduct[];
}

export interface CommandCenterWorkspace {
  workspaceId: string;
  displayName: string;
  handle: string;
  state: string;
  aliases: string[];
}

export interface CommandCenterProduct {
  productId: string;
  displayName: string;
  slug: string;
  state: string;
  version: number;
  aliases: string[];
  projects: CommandCenterProject[];
}

export interface CommandCenterProject {
  projectId: string;
  workspaceId: string;
  displayName: string;
  slug: string;
  state: string;
  version: number;
  aliases: string[];
  tasks: CommandCenterTask[];
}

export interface CommandCenterTask {
  taskId: string;
  workspaceId: string;
  displayName: string;
  slug: string;
  objective: string;
  lifecycleState: string;
  version: number;
  aliases: string[];
  activeBlockers: CommandCenterBlocker[];
  recentResults: CommandCenterResult[];
}

export interface CommandCenterBlocker {
  blockerId: string;
  summary: string;
  createdAt: string;
}

export interface CommandCenterResult {
  resultId: string;
  summary: string;
  verificationState: string;
  recordedAt: string;
}

const forbiddenClientKeys = new Set([
  "accountId", "path", "cwd", "provider", "providerId", "providerThreadId", "credential", "transcript", "audio", "rawOutput", "codex",
]);

export function isCommandCenterSnapshot(value: unknown): value is CommandCenterSnapshot {
  if (!isRecord(value) || containsForbiddenKey(value)) return false;
  return hasExactKeys(value, ["schemaVersion", "observedAt", "workspaces", "products"])
    && value.schemaVersion === 1
    && isTimestamp(value.observedAt)
    && isArrayOf(value.workspaces, isWorkspace)
    && isArrayOf(value.products, isProduct);
}

function isWorkspace(value: unknown): value is CommandCenterWorkspace {
  return isRecord(value)
    && hasExactKeys(value, ["workspaceId", "displayName", "handle", "state", "aliases"])
    && strings(value, ["workspaceId", "displayName", "handle", "state"])
    && isStringArray(value.aliases);
}

function isProduct(value: unknown): value is CommandCenterProduct {
  return isRecord(value)
    && hasExactKeys(value, ["productId", "displayName", "slug", "state", "version", "aliases", "projects"])
    && strings(value, ["productId", "displayName", "slug", "state"])
    && isVersion(value.version)
    && isStringArray(value.aliases)
    && isArrayOf(value.projects, isProject);
}

function isProject(value: unknown): value is CommandCenterProject {
  return isRecord(value)
    && hasExactKeys(value, ["projectId", "workspaceId", "displayName", "slug", "state", "version", "aliases", "tasks"])
    && strings(value, ["projectId", "workspaceId", "displayName", "slug", "state"])
    && isVersion(value.version)
    && isStringArray(value.aliases)
    && isArrayOf(value.tasks, isTask);
}

function isTask(value: unknown): value is CommandCenterTask {
  return isRecord(value)
    && hasExactKeys(value, ["taskId", "workspaceId", "displayName", "slug", "objective", "lifecycleState", "version", "aliases", "activeBlockers", "recentResults"])
    && strings(value, ["taskId", "workspaceId", "displayName", "slug", "objective", "lifecycleState"])
    && isVersion(value.version)
    && isStringArray(value.aliases)
    && isArrayOf(value.activeBlockers, isBlocker)
    && isArrayOf(value.recentResults, isResult);
}

function isBlocker(value: unknown): value is CommandCenterBlocker {
  return isRecord(value)
    && hasExactKeys(value, ["blockerId", "summary", "createdAt"])
    && strings(value, ["blockerId", "summary"])
    && isTimestamp(value.createdAt);
}

function isResult(value: unknown): value is CommandCenterResult {
  return isRecord(value)
    && hasExactKeys(value, ["resultId", "summary", "verificationState", "recordedAt"])
    && strings(value, ["resultId", "summary", "verificationState"])
    && isTimestamp(value.recordedAt);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, keys: string[]): boolean {
  const actual = Object.keys(value).sort();
  return actual.length === keys.length && keys.slice().sort().every((key, index) => key === actual[index]);
}

function strings(value: Record<string, unknown>, keys: string[]): boolean {
  return keys.every((key) => typeof value[key] === "string" && (value[key] as string).length > 0);
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((entry) => typeof entry === "string" && entry.length > 0);
}

function isArrayOf<T>(value: unknown, guard: (entry: unknown) => entry is T): value is T[] {
  return Array.isArray(value) && value.every(guard);
}

function isVersion(value: unknown): value is number {
  return Number.isSafeInteger(value) && Number(value) > 0;
}

function isIntegerBetween(value: unknown, minimum: number, maximum: number): value is number {
  return Number.isSafeInteger(value) && Number(value) >= minimum && Number(value) <= maximum;
}

function nonemptyString(value: unknown): value is string {
  return typeof value === "string" && value.length > 0;
}

function isTimestamp(value: unknown): value is string {
  return typeof value === "string"
    && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value)
    && !Number.isNaN(Date.parse(value));
}

function containsForbiddenKey(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(containsForbiddenKey);
  if (!isRecord(value)) return false;
  return Object.entries(value).some(([key, child]) => forbiddenClientKeys.has(key) || containsForbiddenKey(child));
}

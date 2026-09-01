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

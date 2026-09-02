// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

export class DomainNotFoundError extends Error {
  constructor(entity: string) {
    super(`${entity} was not found in the authorized account scope`);
    this.name = "DomainNotFoundError";
  }
}

export class StaleVersionError extends Error {
  constructor(readonly currentVersion: number) {
    super(`Expected aggregate version is stale; current version is ${currentVersion}`);
    this.name = "StaleVersionError";
  }
}

export class IdempotencyConflictError extends Error {
  constructor() {
    super("Idempotency key was already used for a different request fingerprint");
    this.name = "IdempotencyConflictError";
  }
}

export interface ReferenceCandidate {
  entityId: string;
  displayName: string;
  slug: string;
  parentId?: string;
  parentDisplayName?: string;
}

export class InvalidReferenceError extends Error {
  constructor() {
    super("Portfolio reference must contain a name, alias, or Conatus identifier");
    this.name = "InvalidReferenceError";
  }
}

export class InvalidSummaryError extends Error {
  constructor() {
    super("Task blocker and result summaries cannot be empty");
    this.name = "InvalidSummaryError";
  }
}

export class AmbiguousReferenceError extends Error {
  constructor(
    readonly entityType: string,
    readonly reference: string,
    readonly candidates: readonly ReferenceCandidate[],
  ) {
    super(`Portfolio reference '${reference}' is ambiguous for ${entityType}`);
    this.name = "AmbiguousReferenceError";
  }
}

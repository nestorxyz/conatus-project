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

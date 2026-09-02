// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import type { PoolClient } from "pg";
import { DomainNotFoundError } from "../domain/errors.js";
import { uuidV7 } from "../domain/ids.js";

export interface DomainEventInput {
  accountId: string;
  aggregateType: string;
  aggregateId: string;
  aggregateVersion: number;
  eventType: string;
  actorRef: string;
  correlationId: string;
  causationId?: string;
  recordedAt?: Date;
  payload: Record<string, unknown>;
}

export async function appendDomainEvent(client: PoolClient, input: DomainEventInput): Promise<void> {
  const position = await client.query<{ next_position: string }>(
    "UPDATE account_sequences SET next_position = next_position + 1 WHERE account_id = $1 RETURNING next_position",
    [input.accountId],
  );
  if (!position.rowCount) throw new DomainNotFoundError("Account sequence");
  const eventId = uuidV7();
  const recordedAt = input.recordedAt ?? new Date();
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

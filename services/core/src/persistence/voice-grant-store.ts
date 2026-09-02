// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { createHash, randomBytes } from "node:crypto";
import { Pool, type PoolClient } from "pg";
import {
  DomainNotFoundError,
  InvalidVoiceGrantError,
  VoiceGrantLimitError,
  VoiceQuotaExceededError,
} from "../domain/errors.js";
import { uuidV7 } from "../domain/ids.js";
import type { IssuedVoiceGrant, VoiceGrantUsage, VoiceQuotaEvidence } from "../domain/types.js";
import { appendDomainEvent } from "./domain-events.js";

interface VoiceQuotaRow {
  daily_audio_ms_limit: string;
  active_grant_limit: number;
  max_grant_audio_ms: number;
  max_grant_turns: number;
  grant_ttl_seconds: number;
}

interface VoiceGrantRow {
  voice_grant_id: string;
  principal_id: string;
  state: "active" | "revoked" | "expired" | "exhausted";
  usage_date: string | Date;
  remaining_audio_ms: number;
  remaining_turns: number;
  version: string;
  expires_at: Date;
}

export class VoiceGrantStore {
  private readonly pool: Pool;

  constructor(connectionString: string) {
    this.pool = new Pool({ connectionString, max: 8 });
  }

  async close(): Promise<void> {
    await this.pool.end();
  }

  async issueVoiceGrant(input: {
    accountId: string;
    principalId: string;
    requestedAudioMilliseconds: number;
    requestedTurns: number;
    now?: Date;
  }): Promise<IssuedVoiceGrant> {
    const now = input.now ?? new Date();
    return this.transaction(async (client) => {
      const quota = await this.lockQuota(client, input.accountId, input.principalId);
      await this.cleanupExpiredWith(client, input.accountId, now);
      guardRequestedAllowance(input, quota);

      const active = await client.query<{ count: string }>(
        "SELECT count(*) FROM voice_grants WHERE account_id = $1 AND state = 'active'",
        [input.accountId],
      );
      if (Number(active.rows[0]!.count) >= quota.active_grant_limit) {
        throw new VoiceGrantLimitError();
      }

      const usageDate = utcDate(now);
      await client.query(
        `INSERT INTO voice_usage_days (account_id, usage_date, updated_at)
         VALUES ($1, $2, $3) ON CONFLICT (account_id, usage_date) DO NOTHING`,
        [input.accountId, usageDate, now],
      );
      const usage = await client.query<{ consumed_audio_ms: string; reserved_audio_ms: string }>(
        `SELECT consumed_audio_ms, reserved_audio_ms FROM voice_usage_days
         WHERE account_id = $1 AND usage_date = $2 FOR UPDATE`,
        [input.accountId, usageDate],
      );
      const used = Number(usage.rows[0]!.consumed_audio_ms) + Number(usage.rows[0]!.reserved_audio_ms);
      if (used + input.requestedAudioMilliseconds > Number(quota.daily_audio_ms_limit)) {
        throw new VoiceQuotaExceededError();
      }

      const voiceGrantId = uuidV7();
      const relayToken = randomBytes(32).toString("base64url");
      const expiresAt = new Date(now.getTime() + quota.grant_ttl_seconds * 1_000);
      await client.query(
        `UPDATE voice_usage_days
         SET reserved_audio_ms = reserved_audio_ms + $3, version = version + 1, updated_at = $4
         WHERE account_id = $1 AND usage_date = $2`,
        [input.accountId, usageDate, input.requestedAudioMilliseconds, now],
      );
      await client.query(
        `INSERT INTO voice_grants
          (account_id, voice_grant_id, principal_id, relay_token_sha256, scope, state, usage_date,
           max_audio_ms, remaining_audio_ms, max_turns, remaining_turns, version, issued_at, expires_at)
         VALUES ($1, $2, $3, $4, 'transcribe_post_wake_audio', 'active', $5,
           $6, $6, $7, $7, 1, $8, $9)`,
        [input.accountId, voiceGrantId, input.principalId, tokenDigest(relayToken), usageDate,
          input.requestedAudioMilliseconds, input.requestedTurns, now, expiresAt],
      );
      await appendDomainEvent(client, {
        accountId: input.accountId,
        aggregateType: "VoiceGrant",
        aggregateId: voiceGrantId,
        aggregateVersion: 1,
        eventType: "VoiceGrantIssued",
        actorRef: `principal:${input.principalId}`,
        correlationId: uuidV7(),
        recordedAt: now,
        payload: {
          scope: "transcribe_post_wake_audio",
          maxAudioMilliseconds: input.requestedAudioMilliseconds,
          maxTurns: input.requestedTurns,
          expiresAt: expiresAt.toISOString(),
        },
      });
      return {
        schemaVersion: 1,
        voiceGrantId,
        relayToken,
        scope: "transcribe_post_wake_audio",
        issuedAt: now.toISOString(),
        expiresAt: expiresAt.toISOString(),
        maxAudioMilliseconds: input.requestedAudioMilliseconds,
        maxTurns: input.requestedTurns,
      };
    });
  }

  async consumeVoiceGrant(input: {
    accountId: string;
    principalId: string;
    relayToken: string;
    audioMilliseconds: number;
    now?: Date;
  }): Promise<VoiceGrantUsage> {
    const now = input.now ?? new Date();
    if (!Number.isSafeInteger(input.audioMilliseconds) || input.audioMilliseconds <= 0) {
      throw new VoiceQuotaExceededError();
    }
    return this.transaction(async (client) => {
      await this.lockQuota(client, input.accountId, input.principalId);
      await this.cleanupExpiredWith(client, input.accountId, now);
      const grant = await this.findActiveGrant(
        client,
        input.accountId,
        input.principalId,
        input.relayToken,
      );
      if (input.audioMilliseconds > grant.remaining_audio_ms || grant.remaining_turns < 1) {
        throw new VoiceQuotaExceededError();
      }

      const afterAudio = grant.remaining_audio_ms - input.audioMilliseconds;
      const afterTurns = grant.remaining_turns - 1;
      const exhausted = afterAudio === 0 || afterTurns === 0;
      const releasedAudio = exhausted ? afterAudio : 0;
      const remainingAudio = exhausted ? 0 : afterAudio;
      const remainingTurns = exhausted ? 0 : afterTurns;
      const nextState = exhausted ? "exhausted" : "active";
      const updated = await client.query<{ version: string }>(
        `UPDATE voice_grants SET state = $4, remaining_audio_ms = $5, remaining_turns = $6,
           version = version + 1, last_used_at = $7
         WHERE account_id = $1 AND voice_grant_id = $2 AND version = $3
         RETURNING version`,
        [input.accountId, grant.voice_grant_id, grant.version, nextState, remainingAudio, remainingTurns, now],
      );
      if (!updated.rowCount) throw new InvalidVoiceGrantError();
      await client.query(
        `UPDATE voice_usage_days SET
           consumed_audio_ms = consumed_audio_ms + $3,
           reserved_audio_ms = reserved_audio_ms - $4,
           version = version + 1, updated_at = $5
         WHERE account_id = $1 AND usage_date = $2`,
        [input.accountId, grant.usage_date, input.audioMilliseconds,
          input.audioMilliseconds + releasedAudio, now],
      );
      await appendDomainEvent(client, {
        accountId: input.accountId,
        aggregateType: "VoiceGrant",
        aggregateId: grant.voice_grant_id,
        aggregateVersion: Number(updated.rows[0]!.version),
        eventType: exhausted ? "VoiceGrantExhausted" : "VoiceGrantUsed",
        actorRef: "service:voice-relay",
        correlationId: uuidV7(),
        recordedAt: now,
        payload: {
          audioMilliseconds: input.audioMilliseconds,
          remainingAudioMilliseconds: remainingAudio,
          remainingTurns,
          releasedAudioMilliseconds: releasedAudio,
        },
      });
      return {
        voiceGrantId: grant.voice_grant_id,
        state: nextState,
        remainingAudioMilliseconds: remainingAudio,
        remainingTurns,
      };
    });
  }

  async revokeVoiceGrant(input: {
    accountId: string;
    principalId: string;
    voiceGrantId: string;
    now?: Date;
  }): Promise<void> {
    const now = input.now ?? new Date();
    await this.transaction(async (client) => {
      await this.lockQuota(client, input.accountId, input.principalId);
      await this.cleanupExpiredWith(client, input.accountId, now);
      const result = await client.query<VoiceGrantRow>(
        `SELECT voice_grant_id, principal_id, state, usage_date, remaining_audio_ms,
           remaining_turns, version, expires_at
         FROM voice_grants
         WHERE account_id = $1 AND voice_grant_id = $2 AND principal_id = $3 FOR UPDATE`,
        [input.accountId, input.voiceGrantId, input.principalId],
      );
      const grant = result.rows[0];
      if (!grant) throw new DomainNotFoundError("Voice grant");
      if (grant.state !== "active") return;
      await this.releaseGrant(client, input.accountId, grant, "revoked", now,
        `principal:${input.principalId}`);
    });
  }

  async cleanupExpiredGrants(accountId: string, now: Date = new Date()): Promise<number> {
    return this.transaction(async (client) => {
      await this.lockQuotaForAccount(client, accountId);
      return this.cleanupExpiredWith(client, accountId, now);
    });
  }

  async quotaEvidence(accountId: string, now: Date = new Date()): Promise<VoiceQuotaEvidence> {
    const usageDate = utcDate(now);
    const result = await this.pool.query<{
      active_grants: string;
      consumed_audio_ms: string;
      reserved_audio_ms: string;
    }>(
      `SELECT
         (SELECT count(*) FROM voice_grants
          WHERE account_id = $1 AND state = 'active' AND expires_at > $3) AS active_grants,
         coalesce((SELECT consumed_audio_ms FROM voice_usage_days
          WHERE account_id = $1 AND usage_date = $2), 0) AS consumed_audio_ms,
         coalesce((SELECT reserved_audio_ms FROM voice_usage_days
          WHERE account_id = $1 AND usage_date = $2), 0) AS reserved_audio_ms`,
      [accountId, usageDate, now],
    );
    const row = result.rows[0]!;
    return {
      activeGrantCount: Number(row.active_grants),
      consumedAudioMilliseconds: Number(row.consumed_audio_ms),
      reservedAudioMilliseconds: Number(row.reserved_audio_ms),
    };
  }

  private async lockQuota(
    client: PoolClient,
    accountId: string,
    principalId: string,
  ): Promise<VoiceQuotaRow> {
    const quota = await this.lockQuotaForAccount(client, accountId);
    const principal = await client.query(
      `SELECT 1 FROM principals
       WHERE account_id = $1 AND principal_id = $2 AND state = 'active'`,
      [accountId, principalId],
    );
    if (!principal.rowCount) throw new DomainNotFoundError("Voice principal");
    return quota;
  }

  private async lockQuotaForAccount(client: PoolClient, accountId: string): Promise<VoiceQuotaRow> {
    const quota = await client.query<VoiceQuotaRow>(
      `SELECT q.daily_audio_ms_limit, q.active_grant_limit, q.max_grant_audio_ms,
         q.max_grant_turns, q.grant_ttl_seconds
       FROM voice_account_quotas q JOIN accounts a ON a.account_id = q.account_id
       WHERE q.account_id = $1 AND a.state = 'active' FOR UPDATE OF q`,
      [accountId],
    );
    if (!quota.rowCount) throw new DomainNotFoundError("Voice quota");
    return quota.rows[0]!;
  }

  private async findActiveGrant(
    client: PoolClient,
    accountId: string,
    principalId: string,
    relayToken: string,
  ): Promise<VoiceGrantRow> {
    if (!/^[A-Za-z0-9_-]{43}$/.test(relayToken)) throw new InvalidVoiceGrantError();
    const result = await client.query<VoiceGrantRow>(
      `SELECT voice_grant_id, principal_id, state, usage_date, remaining_audio_ms,
         remaining_turns, version, expires_at
       FROM voice_grants
       WHERE account_id = $1 AND principal_id = $2 AND relay_token_sha256 = $3
         AND state = 'active' FOR UPDATE`,
      [accountId, principalId, tokenDigest(relayToken)],
    );
    if (!result.rowCount) throw new InvalidVoiceGrantError();
    return result.rows[0]!;
  }

  private async cleanupExpiredWith(client: PoolClient, accountId: string, now: Date): Promise<number> {
    const expired = await client.query<VoiceGrantRow>(
      `SELECT voice_grant_id, principal_id, state, usage_date, remaining_audio_ms,
         remaining_turns, version, expires_at
       FROM voice_grants
       WHERE account_id = $1 AND state = 'active' AND expires_at <= $2
       ORDER BY expires_at, voice_grant_id FOR UPDATE`,
      [accountId, now],
    );
    for (const grant of expired.rows) {
      await this.releaseGrant(client, accountId, grant, "expired", now, "service:voice-cleanup");
    }
    return expired.rowCount ?? 0;
  }

  private async releaseGrant(
    client: PoolClient,
    accountId: string,
    grant: VoiceGrantRow,
    state: "revoked" | "expired",
    now: Date,
    actorRef: string,
  ): Promise<void> {
    const updated = await client.query<{ version: string }>(
      `UPDATE voice_grants SET state = $4, remaining_audio_ms = 0, remaining_turns = 0,
         version = version + 1,
         revoked_at = CASE WHEN $4::text = 'revoked' THEN $5::timestamptz ELSE NULL END
       WHERE account_id = $1 AND voice_grant_id = $2 AND version = $3
       RETURNING version`,
      [accountId, grant.voice_grant_id, grant.version, state, now],
    );
    if (!updated.rowCount) throw new InvalidVoiceGrantError();
    await client.query(
      `UPDATE voice_usage_days SET reserved_audio_ms = reserved_audio_ms - $3,
         version = version + 1, updated_at = $4
       WHERE account_id = $1 AND usage_date = $2`,
      [accountId, grant.usage_date, grant.remaining_audio_ms, now],
    );
    await appendDomainEvent(client, {
      accountId,
      aggregateType: "VoiceGrant",
      aggregateId: grant.voice_grant_id,
      aggregateVersion: Number(updated.rows[0]!.version),
      eventType: state === "revoked" ? "VoiceGrantRevoked" : "VoiceGrantExpired",
      actorRef,
      correlationId: uuidV7(),
      recordedAt: now,
      payload: { releasedAudioMilliseconds: grant.remaining_audio_ms },
    });
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
}

function guardRequestedAllowance(
  input: { requestedAudioMilliseconds: number; requestedTurns: number },
  quota: VoiceQuotaRow,
): void {
  if (
    !Number.isSafeInteger(input.requestedAudioMilliseconds)
    || input.requestedAudioMilliseconds < 1_000
    || input.requestedAudioMilliseconds > quota.max_grant_audio_ms
    || !Number.isSafeInteger(input.requestedTurns)
    || input.requestedTurns < 1
    || input.requestedTurns > quota.max_grant_turns
  ) {
    throw new VoiceQuotaExceededError();
  }
}

function tokenDigest(relayToken: string): string {
  return createHash("sha256").update(relayToken, "utf8").digest("hex");
}

function utcDate(now: Date): string {
  return now.toISOString().slice(0, 10);
}

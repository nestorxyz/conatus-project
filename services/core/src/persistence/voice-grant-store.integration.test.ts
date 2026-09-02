// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import assert from "node:assert/strict";
import { test } from "node:test";
import { Pool } from "pg";
import {
  InvalidVoiceGrantError,
  VoiceGrantLimitError,
  VoiceQuotaExceededError,
} from "../domain/errors.js";
import { uuidV7 } from "../domain/ids.js";
import { DomainStore } from "./domain-store.js";
import { VoiceGrantStore } from "./voice-grant-store.js";

const databaseUrl = process.env.CONATUS_TEST_DATABASE_URL;

test("M2-03 durable account voice grants", { skip: !databaseUrl }, async (context) => {
  const domains = new DomainStore(databaseUrl!);
  const grants = new VoiceGrantStore(databaseUrl!);
  const inspection = new Pool({ connectionString: databaseUrl!, max: 2 });
  await domains.migrate();
  context.after(async () => {
    await Promise.all([domains.close(), grants.close(), inspection.end()]);
  });

  await context.test("persists one-time relay tokens as digest-only bounded grants", async () => {
    const owner = await domains.createAccount("Voice token account", "Voice owner");
    const issuedAt = new Date("2026-09-02T15:00:00.000Z");
    const grant = await grants.issueVoiceGrant({
      ...owner,
      requestedAudioMilliseconds: 2_000,
      requestedTurns: 2,
      now: issuedAt,
    });
    assert.equal(grant.expiresAt, "2026-09-02T15:05:00.000Z");
    assert.equal(grant.relayToken.length, 43);
    assert.equal(JSON.stringify(grant).includes("provider"), false);
    assert.deepEqual(await grants.quotaEvidence(owner.accountId, issuedAt), {
      activeGrantCount: 1,
      consumedAudioMilliseconds: 0,
      reservedAudioMilliseconds: 2_000,
    });

    const stored = await inspection.query<{ relay_token_sha256: string }>(
      "SELECT relay_token_sha256 FROM voice_grants WHERE account_id = $1 AND voice_grant_id = $2",
      [owner.accountId, grant.voiceGrantId],
    );
    assert.equal(stored.rows[0]!.relay_token_sha256.length, 64);
    assert.notEqual(stored.rows[0]!.relay_token_sha256, grant.relayToken);
    const columns = await inspection.query<{ column_name: string }>(
      `SELECT column_name FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'voice_grants'`,
    );
    assert.equal(columns.rows.some((row) => row.column_name === "relay_token"), false);
    const evidence = await inspection.query<{ evidence: string }>(
      `SELECT coalesce(string_agg(payload::text, ' '), '') AS evidence FROM (
         SELECT payload FROM domain_events
         WHERE account_id = $1 AND aggregate_type = 'VoiceGrant'
         UNION ALL
         SELECT o.payload FROM outbox_records o JOIN domain_events e
           ON e.account_id = o.account_id AND e.event_id = o.event_id
         WHERE e.account_id = $1 AND e.aggregate_type = 'VoiceGrant'
       ) durable_evidence`,
      [owner.accountId],
    );
    for (const forbidden of [grant.relayToken, stored.rows[0]!.relay_token_sha256, "provider", "transcript"]) {
      assert.equal(evidence.rows[0]!.evidence.includes(forbidden), false, `event exposed ${forbidden}`);
    }

    const restarted = new VoiceGrantStore(databaseUrl!);
    context.after(async () => restarted.close());
    const first = await restarted.consumeVoiceGrant({
      ...owner,
      relayToken: grant.relayToken,
      audioMilliseconds: 1_000,
      now: new Date("2026-09-02T15:01:00.000Z"),
    });
    assert.equal(first.state, "active");
    assert.equal(first.remainingTurns, 1);
    const second = await restarted.consumeVoiceGrant({
      ...owner,
      relayToken: grant.relayToken,
      audioMilliseconds: 1_000,
      now: new Date("2026-09-02T15:02:00.000Z"),
    });
    assert.equal(second.state, "exhausted");
    assert.equal(second.remainingTurns, 0);
    assert.deepEqual(await grants.quotaEvidence(owner.accountId, issuedAt), {
      activeGrantCount: 0,
      consumedAudioMilliseconds: 2_000,
      reservedAudioMilliseconds: 0,
    });
    await assert.rejects(
      grants.consumeVoiceGrant({
        ...owner,
        relayToken: grant.relayToken,
        audioMilliseconds: 1_000,
        now: new Date("2026-09-02T15:03:00.000Z"),
      }),
      InvalidVoiceGrantError,
    );
  });

  await context.test("serializes concurrent issue and hides cross-account or cross-principal grants", async () => {
    const owner = await domains.createAccount("Voice concurrency account", "Concurrency owner");
    const other = await domains.createAccount("Other voice account", "Other owner");
    const now = new Date("2026-09-02T16:00:00.000Z");
    const outcomes = await Promise.allSettled([
      grants.issueVoiceGrant({ ...owner, requestedAudioMilliseconds: 1_000, requestedTurns: 1, now }),
      grants.issueVoiceGrant({ ...owner, requestedAudioMilliseconds: 1_000, requestedTurns: 1, now }),
    ]);
    assert.equal(outcomes.filter((outcome) => outcome.status === "fulfilled").length, 1);
    const rejection = outcomes.find((outcome) => outcome.status === "rejected");
    assert.equal(rejection?.status === "rejected" && rejection.reason instanceof VoiceGrantLimitError, true);
    const granted = outcomes.find((outcome) => outcome.status === "fulfilled");
    assert.equal(granted?.status, "fulfilled");
    if (granted?.status !== "fulfilled") throw new Error("expected one issued grant");

    await assert.rejects(
      grants.consumeVoiceGrant({
        ...other,
        relayToken: granted.value.relayToken,
        audioMilliseconds: 1_000,
        now,
      }),
      InvalidVoiceGrantError,
    );
    const secondPrincipalId = uuidV7();
    await inspection.query(
      `INSERT INTO principals
        (account_id, principal_id, display_name, state, version, created_at, updated_at, created_by, updated_by)
       VALUES ($1, $2, 'Second principal', 'active', 1, $3, $3, 'test', 'test')`,
      [owner.accountId, secondPrincipalId, now],
    );
    await assert.rejects(
      grants.consumeVoiceGrant({
        accountId: owner.accountId,
        principalId: secondPrincipalId,
        relayToken: granted.value.relayToken,
        audioMilliseconds: 1_000,
        now,
      }),
      InvalidVoiceGrantError,
    );
    await grants.revokeVoiceGrant({ ...owner, voiceGrantId: granted.value.voiceGrantId, now });
    await grants.revokeVoiceGrant({ ...owner, voiceGrantId: granted.value.voiceGrantId, now });
    assert.equal((await grants.quotaEvidence(owner.accountId, now)).reservedAudioMilliseconds, 0);
    await assert.rejects(
      grants.consumeVoiceGrant({
        ...owner,
        relayToken: granted.value.relayToken,
        audioMilliseconds: 1_000,
        now,
      }),
      InvalidVoiceGrantError,
    );
  });

  await context.test("admits one concurrent relay use and rejects its replay", async () => {
    const owner = await domains.createAccount("Voice relay race account", "Relay owner");
    const now = new Date("2026-09-02T16:30:00.000Z");
    const grant = await grants.issueVoiceGrant({
      ...owner,
      requestedAudioMilliseconds: 1_000,
      requestedTurns: 1,
      now,
    });
    const outcomes = await Promise.allSettled([
      grants.consumeVoiceGrant({ ...owner, relayToken: grant.relayToken, audioMilliseconds: 1_000, now }),
      grants.consumeVoiceGrant({ ...owner, relayToken: grant.relayToken, audioMilliseconds: 1_000, now }),
    ]);
    assert.equal(outcomes.filter((outcome) => outcome.status === "fulfilled").length, 1);
    const rejection = outcomes.find((outcome) => outcome.status === "rejected");
    assert.equal(rejection?.status === "rejected" && rejection.reason instanceof InvalidVoiceGrantError, true);
    assert.deepEqual(await grants.quotaEvidence(owner.accountId, now), {
      activeGrantCount: 0,
      consumedAudioMilliseconds: 1_000,
      reservedAudioMilliseconds: 0,
    });
  });

  await context.test("reclaims abandoned grants idempotently", async () => {
    const owner = await domains.createAccount("Voice cleanup account", "Cleanup owner");
    const issuedAt = new Date("2026-09-02T17:00:00.000Z");
    const grant = await grants.issueVoiceGrant({
      ...owner,
      requestedAudioMilliseconds: 10_000,
      requestedTurns: 2,
      now: issuedAt,
    });
    const expiredAt = new Date("2026-09-02T17:06:00.000Z");
    assert.equal(await grants.cleanupExpiredGrants(owner.accountId, expiredAt), 1);
    assert.equal(await grants.cleanupExpiredGrants(owner.accountId, expiredAt), 0);
    assert.deepEqual(await grants.quotaEvidence(owner.accountId, expiredAt), {
      activeGrantCount: 0,
      consumedAudioMilliseconds: 0,
      reservedAudioMilliseconds: 0,
    });
    await assert.rejects(
      grants.consumeVoiceGrant({
        ...owner,
        relayToken: grant.relayToken,
        audioMilliseconds: 1_000,
        now: expiredAt,
      }),
      InvalidVoiceGrantError,
    );
  });

  await context.test("enforces the durable account-day quota", async () => {
    const owner = await domains.createAccount("Voice quota account", "Quota owner");
    const now = new Date("2026-09-02T18:00:00.000Z");
    await inspection.query(
      `UPDATE voice_account_quotas
       SET daily_audio_ms_limit = 3000, max_grant_audio_ms = 3000, updated_at = $2, updated_by = 'test'
       WHERE account_id = $1`,
      [owner.accountId, now],
    );
    const grant = await grants.issueVoiceGrant({
      ...owner,
      requestedAudioMilliseconds: 3_000,
      requestedTurns: 1,
      now,
    });
    await grants.consumeVoiceGrant({
      ...owner,
      relayToken: grant.relayToken,
      audioMilliseconds: 3_000,
      now,
    });
    await assert.rejects(
      grants.issueVoiceGrant({
        ...owner,
        requestedAudioMilliseconds: 1_000,
        requestedTurns: 1,
        now,
      }),
      VoiceQuotaExceededError,
    );
  });
});

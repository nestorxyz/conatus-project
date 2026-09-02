-- SPDX-FileCopyrightText: 2026 Conatus contributors
-- SPDX-License-Identifier: AGPL-3.0-or-later

BEGIN;

CREATE TABLE IF NOT EXISTS voice_account_quotas (
  account_id uuid PRIMARY KEY REFERENCES accounts(account_id),
  daily_audio_ms_limit bigint NOT NULL DEFAULT 3600000 CHECK (daily_audio_ms_limit > 0),
  active_grant_limit integer NOT NULL DEFAULT 1 CHECK (active_grant_limit > 0),
  max_grant_audio_ms integer NOT NULL DEFAULT 300000 CHECK (max_grant_audio_ms BETWEEN 1000 AND 300000),
  max_grant_turns integer NOT NULL DEFAULT 10 CHECK (max_grant_turns BETWEEN 1 AND 10),
  grant_ttl_seconds integer NOT NULL DEFAULT 300 CHECK (grant_ttl_seconds BETWEEN 30 AND 300),
  updated_at timestamptz NOT NULL,
  updated_by text NOT NULL
);

INSERT INTO voice_account_quotas (account_id, updated_at, updated_by)
SELECT account_id, clock_timestamp(), 'migration:003'
FROM accounts
ON CONFLICT (account_id) DO NOTHING;

CREATE TABLE IF NOT EXISTS voice_usage_days (
  account_id uuid NOT NULL REFERENCES accounts(account_id),
  usage_date date NOT NULL,
  consumed_audio_ms bigint NOT NULL DEFAULT 0 CHECK (consumed_audio_ms >= 0),
  reserved_audio_ms bigint NOT NULL DEFAULT 0 CHECK (reserved_audio_ms >= 0),
  version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (account_id, usage_date)
);

CREATE TABLE IF NOT EXISTS voice_grants (
  account_id uuid NOT NULL,
  voice_grant_id uuid NOT NULL,
  principal_id uuid NOT NULL,
  relay_token_sha256 char(64) NOT NULL UNIQUE CHECK (relay_token_sha256 ~ '^[0-9a-f]{64}$'),
  scope text NOT NULL CHECK (scope = 'transcribe_post_wake_audio'),
  state text NOT NULL CHECK (state IN ('active', 'revoked', 'expired', 'exhausted')),
  usage_date date NOT NULL,
  max_audio_ms integer NOT NULL CHECK (max_audio_ms BETWEEN 1000 AND 300000),
  remaining_audio_ms integer NOT NULL CHECK (remaining_audio_ms BETWEEN 0 AND 300000),
  max_turns integer NOT NULL CHECK (max_turns BETWEEN 1 AND 10),
  remaining_turns integer NOT NULL CHECK (remaining_turns BETWEEN 0 AND 10),
  version bigint NOT NULL CHECK (version > 0),
  issued_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  last_used_at timestamptz,
  revoked_at timestamptz,
  PRIMARY KEY (account_id, voice_grant_id),
  FOREIGN KEY (account_id, principal_id) REFERENCES principals(account_id, principal_id),
  FOREIGN KEY (account_id, usage_date) REFERENCES voice_usage_days(account_id, usage_date),
  CHECK (expires_at > issued_at),
  CHECK (remaining_audio_ms <= max_audio_ms),
  CHECK (remaining_turns <= max_turns),
  CHECK ((state = 'active' AND remaining_audio_ms > 0 AND remaining_turns > 0)
    OR (state <> 'active' AND remaining_audio_ms = 0 AND remaining_turns = 0)),
  CHECK ((state = 'revoked' AND revoked_at IS NOT NULL)
    OR (state <> 'revoked' AND revoked_at IS NULL))
);

CREATE INDEX IF NOT EXISTS voice_grants_active_account_idx
  ON voice_grants(account_id, state, expires_at);

CREATE INDEX IF NOT EXISTS voice_grants_expiry_idx
  ON voice_grants(expires_at) WHERE state = 'active';

INSERT INTO schema_migrations(version) VALUES (3)
ON CONFLICT (version) DO NOTHING;

COMMIT;

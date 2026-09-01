-- SPDX-FileCopyrightText: 2026 Conatus contributors
-- SPDX-License-Identifier: AGPL-3.0-or-later

BEGIN;

CREATE TABLE IF NOT EXISTS schema_migrations (
  version integer PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS accounts (
  account_id uuid PRIMARY KEY,
  display_name text NOT NULL CHECK (length(display_name) > 0),
  state text NOT NULL CHECK (state IN ('active', 'locked', 'closure_pending', 'closed')),
  owner_principal_id uuid NOT NULL,
  version bigint NOT NULL CHECK (version > 0),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  created_by text NOT NULL,
  updated_by text NOT NULL
);

CREATE TABLE IF NOT EXISTS principals (
  account_id uuid NOT NULL REFERENCES accounts(account_id),
  principal_id uuid NOT NULL,
  display_name text NOT NULL CHECK (length(display_name) > 0),
  state text NOT NULL CHECK (state IN ('active', 'locked', 'recovery_required', 'revoked')),
  version bigint NOT NULL CHECK (version > 0),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  created_by text NOT NULL,
  updated_by text NOT NULL,
  PRIMARY KEY (account_id, principal_id)
);

DO $$ BEGIN
  ALTER TABLE accounts ADD CONSTRAINT accounts_owner_principal_fk
    FOREIGN KEY (account_id, owner_principal_id)
    REFERENCES principals(account_id, principal_id)
    DEFERRABLE INITIALLY DEFERRED;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS account_sequences (
  account_id uuid PRIMARY KEY REFERENCES accounts(account_id),
  next_position bigint NOT NULL DEFAULT 0 CHECK (next_position >= 0)
);

CREATE TABLE IF NOT EXISTS devices (
  account_id uuid NOT NULL REFERENCES accounts(account_id),
  device_id uuid NOT NULL,
  principal_id uuid NOT NULL,
  display_name text NOT NULL,
  platform text NOT NULL,
  trust_state text NOT NULL CHECK (trust_state IN ('pairing', 'trusted', 'degraded', 'revoked')),
  version bigint NOT NULL CHECK (version > 0),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  created_by text NOT NULL,
  updated_by text NOT NULL,
  PRIMARY KEY (account_id, device_id),
  FOREIGN KEY (account_id, principal_id) REFERENCES principals(account_id, principal_id)
);

CREATE TABLE IF NOT EXISTS machines (
  account_id uuid NOT NULL REFERENCES accounts(account_id),
  machine_id uuid NOT NULL,
  display_name text NOT NULL,
  platform text NOT NULL CHECK (platform = 'macos'),
  state text NOT NULL CHECK (state IN ('pairing', 'online', 'degraded', 'offline', 'blocked', 'revoked')),
  version bigint NOT NULL CHECK (version > 0),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  created_by text NOT NULL,
  updated_by text NOT NULL,
  PRIMARY KEY (account_id, machine_id)
);

CREATE TABLE IF NOT EXISTS workspaces (
  account_id uuid NOT NULL REFERENCES accounts(account_id),
  workspace_id uuid NOT NULL,
  display_name text NOT NULL,
  slug text NOT NULL,
  state text NOT NULL CHECK (state IN ('active', 'unavailable', 'archived')),
  version bigint NOT NULL CHECK (version > 0),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  created_by text NOT NULL,
  updated_by text NOT NULL,
  PRIMARY KEY (account_id, workspace_id),
  UNIQUE (account_id, slug)
);

CREATE TABLE IF NOT EXISTS products (
  account_id uuid NOT NULL REFERENCES accounts(account_id),
  product_id uuid NOT NULL,
  display_name text NOT NULL,
  slug text NOT NULL,
  state text NOT NULL CHECK (state IN ('active', 'paused', 'archived')),
  version bigint NOT NULL CHECK (version > 0),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  created_by text NOT NULL,
  updated_by text NOT NULL,
  PRIMARY KEY (account_id, product_id),
  UNIQUE (account_id, slug)
);

CREATE TABLE IF NOT EXISTS projects (
  account_id uuid NOT NULL REFERENCES accounts(account_id),
  project_id uuid NOT NULL,
  product_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  display_name text NOT NULL,
  slug text NOT NULL,
  state text NOT NULL CHECK (state IN ('active', 'waiting', 'paused', 'completed', 'archived')),
  version bigint NOT NULL CHECK (version > 0),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  created_by text NOT NULL,
  updated_by text NOT NULL,
  PRIMARY KEY (account_id, project_id),
  UNIQUE (account_id, slug),
  FOREIGN KEY (account_id, product_id) REFERENCES products(account_id, product_id),
  FOREIGN KEY (account_id, workspace_id) REFERENCES workspaces(account_id, workspace_id)
);

CREATE TABLE IF NOT EXISTS tasks (
  account_id uuid NOT NULL REFERENCES accounts(account_id),
  task_id uuid NOT NULL,
  project_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  display_name text NOT NULL,
  slug text NOT NULL,
  objective text NOT NULL,
  lifecycle_state text NOT NULL CHECK (lifecycle_state IN ('planned', 'ready', 'working', 'blocked', 'waiting_approval', 'verifying', 'completed', 'failed', 'cancelled', 'archived')),
  version bigint NOT NULL CHECK (version > 0),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  created_by text NOT NULL,
  updated_by text NOT NULL,
  PRIMARY KEY (account_id, task_id),
  UNIQUE (account_id, project_id, slug),
  FOREIGN KEY (account_id, project_id) REFERENCES projects(account_id, project_id),
  FOREIGN KEY (account_id, workspace_id) REFERENCES workspaces(account_id, workspace_id)
);

CREATE TABLE IF NOT EXISTS commands (
  account_id uuid NOT NULL REFERENCES accounts(account_id),
  command_id uuid NOT NULL,
  task_id uuid NOT NULL,
  actor_ref text NOT NULL,
  operation_scope text NOT NULL,
  idempotency_key text NOT NULL,
  request_fingerprint text NOT NULL,
  command_type text NOT NULL,
  payload jsonb NOT NULL,
  state text NOT NULL CHECK (state IN ('accepted', 'queued', 'dispatched', 'succeeded', 'failed', 'cancelled', 'outcome_unknown')),
  correlation_id uuid NOT NULL,
  causation_id uuid,
  version bigint NOT NULL CHECK (version > 0),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (account_id, command_id),
  UNIQUE (account_id, actor_ref, operation_scope, idempotency_key),
  FOREIGN KEY (account_id, task_id) REFERENCES tasks(account_id, task_id)
);

CREATE TABLE IF NOT EXISTS deliveries (
  account_id uuid NOT NULL REFERENCES accounts(account_id),
  delivery_id uuid NOT NULL,
  command_id uuid NOT NULL,
  destination_type text NOT NULL,
  state text NOT NULL CHECK (state IN ('queued', 'delivering', 'acknowledged', 'withdrawn', 'expired', 'failed')),
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  actor_ref text NOT NULL,
  correlation_id uuid NOT NULL,
  causation_id uuid NOT NULL,
  version bigint NOT NULL CHECK (version > 0),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (account_id, delivery_id),
  UNIQUE (account_id, command_id),
  FOREIGN KEY (account_id, command_id) REFERENCES commands(account_id, command_id)
);

CREATE TABLE IF NOT EXISTS execution_attempts (
  account_id uuid NOT NULL REFERENCES accounts(account_id),
  execution_attempt_id uuid NOT NULL,
  command_id uuid NOT NULL,
  delivery_id uuid NOT NULL,
  executor_type text NOT NULL,
  state text NOT NULL CHECK (state IN ('accepted', 'starting', 'executing', 'cancel_requested', 'verifying', 'succeeded', 'failed', 'cancelled', 'outcome_unknown')),
  actor_ref text NOT NULL,
  correlation_id uuid NOT NULL,
  causation_id uuid NOT NULL,
  version bigint NOT NULL CHECK (version > 0),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (account_id, execution_attempt_id),
  UNIQUE (account_id, command_id),
  FOREIGN KEY (account_id, command_id) REFERENCES commands(account_id, command_id),
  FOREIGN KEY (account_id, delivery_id) REFERENCES deliveries(account_id, delivery_id)
);

CREATE TABLE IF NOT EXISTS idempotency_records (
  account_id uuid NOT NULL REFERENCES accounts(account_id),
  actor_ref text NOT NULL,
  operation_scope text NOT NULL,
  idempotency_key text NOT NULL,
  request_fingerprint text NOT NULL,
  canonical_entity_type text,
  canonical_entity_id uuid,
  state text NOT NULL CHECK (state IN ('in_progress', 'resolved', 'conflict', 'expired')),
  first_accepted_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  PRIMARY KEY (account_id, actor_ref, operation_scope, idempotency_key)
);

CREATE TABLE IF NOT EXISTS domain_events (
  account_id uuid NOT NULL REFERENCES accounts(account_id),
  event_id uuid NOT NULL,
  account_position bigint NOT NULL CHECK (account_position > 0),
  aggregate_type text NOT NULL,
  aggregate_id uuid NOT NULL,
  aggregate_version bigint NOT NULL CHECK (aggregate_version > 0),
  event_type text NOT NULL,
  schema_version integer NOT NULL CHECK (schema_version > 0),
  actor_ref text NOT NULL,
  correlation_id uuid NOT NULL,
  causation_id uuid,
  recorded_at timestamptz NOT NULL,
  payload jsonb NOT NULL,
  PRIMARY KEY (account_id, event_id),
  UNIQUE (account_id, account_position),
  UNIQUE (account_id, aggregate_type, aggregate_id, aggregate_version)
);

CREATE TABLE IF NOT EXISTS outbox_records (
  account_id uuid NOT NULL REFERENCES accounts(account_id),
  outbox_record_id uuid NOT NULL,
  event_id uuid NOT NULL,
  topic text NOT NULL,
  payload jsonb NOT NULL,
  state text NOT NULL CHECK (state IN ('pending', 'publishing', 'published', 'failed')),
  created_at timestamptz NOT NULL,
  published_at timestamptz,
  PRIMARY KEY (account_id, outbox_record_id),
  UNIQUE (account_id, event_id),
  FOREIGN KEY (account_id, event_id) REFERENCES domain_events(account_id, event_id)
);

INSERT INTO schema_migrations(version) VALUES (1)
ON CONFLICT (version) DO NOTHING;

COMMIT;

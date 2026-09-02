-- SPDX-FileCopyrightText: 2026 Conatus contributors
-- SPDX-License-Identifier: AGPL-3.0-or-later

BEGIN;

CREATE TABLE IF NOT EXISTS workspace_aliases (
  account_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  alias text NOT NULL CHECK (length(alias) > 0),
  normalized_alias text NOT NULL CHECK (normalized_alias ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  created_at timestamptz NOT NULL,
  created_by text NOT NULL,
  PRIMARY KEY (account_id, workspace_id, normalized_alias),
  FOREIGN KEY (account_id, workspace_id) REFERENCES workspaces(account_id, workspace_id)
);

CREATE INDEX IF NOT EXISTS workspace_alias_lookup_idx
  ON workspace_aliases(account_id, normalized_alias);

CREATE TABLE IF NOT EXISTS product_aliases (
  account_id uuid NOT NULL,
  product_id uuid NOT NULL,
  alias text NOT NULL CHECK (length(alias) > 0),
  normalized_alias text NOT NULL CHECK (normalized_alias ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  created_at timestamptz NOT NULL,
  created_by text NOT NULL,
  PRIMARY KEY (account_id, product_id, normalized_alias),
  FOREIGN KEY (account_id, product_id) REFERENCES products(account_id, product_id)
);

CREATE INDEX IF NOT EXISTS product_alias_lookup_idx
  ON product_aliases(account_id, normalized_alias);

CREATE TABLE IF NOT EXISTS project_aliases (
  account_id uuid NOT NULL,
  project_id uuid NOT NULL,
  alias text NOT NULL CHECK (length(alias) > 0),
  normalized_alias text NOT NULL CHECK (normalized_alias ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  created_at timestamptz NOT NULL,
  created_by text NOT NULL,
  PRIMARY KEY (account_id, project_id, normalized_alias),
  FOREIGN KEY (account_id, project_id) REFERENCES projects(account_id, project_id)
);

CREATE INDEX IF NOT EXISTS project_alias_lookup_idx
  ON project_aliases(account_id, normalized_alias);

CREATE TABLE IF NOT EXISTS task_aliases (
  account_id uuid NOT NULL,
  task_id uuid NOT NULL,
  alias text NOT NULL CHECK (length(alias) > 0),
  normalized_alias text NOT NULL CHECK (normalized_alias ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  created_at timestamptz NOT NULL,
  created_by text NOT NULL,
  PRIMARY KEY (account_id, task_id, normalized_alias),
  FOREIGN KEY (account_id, task_id) REFERENCES tasks(account_id, task_id)
);

CREATE INDEX IF NOT EXISTS task_alias_lookup_idx
  ON task_aliases(account_id, normalized_alias);

CREATE TABLE IF NOT EXISTS task_blockers (
  account_id uuid NOT NULL,
  blocker_id uuid NOT NULL,
  task_id uuid NOT NULL,
  summary text NOT NULL CHECK (length(summary) > 0),
  state text NOT NULL CHECK (state IN ('active', 'resolved')),
  created_at timestamptz NOT NULL,
  resolved_at timestamptz,
  created_by text NOT NULL,
  resolved_by text,
  PRIMARY KEY (account_id, blocker_id),
  FOREIGN KEY (account_id, task_id) REFERENCES tasks(account_id, task_id),
  CHECK ((state = 'active' AND resolved_at IS NULL AND resolved_by IS NULL)
    OR (state = 'resolved' AND resolved_at IS NOT NULL AND resolved_by IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS task_blocker_projection_idx
  ON task_blockers(account_id, task_id, state, created_at, blocker_id);

CREATE TABLE IF NOT EXISTS task_results (
  account_id uuid NOT NULL,
  result_id uuid NOT NULL,
  task_id uuid NOT NULL,
  summary text NOT NULL CHECK (length(summary) > 0),
  verification_state text NOT NULL CHECK (verification_state IN ('unverified', 'verified', 'failed')),
  recorded_at timestamptz NOT NULL,
  recorded_by text NOT NULL,
  PRIMARY KEY (account_id, result_id),
  FOREIGN KEY (account_id, task_id) REFERENCES tasks(account_id, task_id)
);

CREATE INDEX IF NOT EXISTS task_result_projection_idx
  ON task_results(account_id, task_id, recorded_at DESC, result_id DESC);

INSERT INTO schema_migrations(version) VALUES (2)
ON CONFLICT (version) DO NOTHING;

COMMIT;

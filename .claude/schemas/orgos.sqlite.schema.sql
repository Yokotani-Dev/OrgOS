-- OrgOS SQLite kernel schema.
-- GPT 4th Q4 baseline tables for local projections and worker coordination.

PRAGMA foreign_keys = ON;
PRAGMA user_version = 1;

CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'paused', 'done', 'cancelled', 'archived')),
  priority TEXT NOT NULL DEFAULT 'P2'
    CHECK (priority IN ('P0', 'P1', 'P2', 'P3')),
  owner TEXT,
  description TEXT NOT NULL DEFAULT '',
  metadata_json TEXT NOT NULL DEFAULT '{}'
    CHECK (json_valid(metadata_json)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  completed_at TEXT
);

CREATE TABLE IF NOT EXISTS workers (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL
    CHECK (kind IN ('manager', 'planner', 'architect', 'implementer', 'reviewer', 'integrator', 'owner', 'system')),
  engine TEXT NOT NULL
    CHECK (engine IN ('claude', 'codex', 'human', 'system')),
  status TEXT NOT NULL DEFAULT 'idle'
    CHECK (status IN ('idle', 'busy', 'blocked', 'offline')),
  current_task_id TEXT,
  capabilities_json TEXT NOT NULL DEFAULT '[]'
    CHECK (json_valid(capabilities_json)),
  metadata_json TEXT NOT NULL DEFAULT '{}'
    CHECK (json_valid(metadata_json)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS tasks (
  id TEXT PRIMARY KEY,
  project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  -- Status vocabulary aligned with the live ledger SSOT
  -- (.claude/evals/check-schema.sh VALID_STATUSES) so the SQLite shadow
  -- projects TASKS.yaml faithfully and generate-dashboard.py can filter
  -- queued/running/in_progress. todo/ready/in_progress retained for
  -- kernel-native lifecycle compatibility.
  status TEXT NOT NULL DEFAULT 'queued'
    CHECK (status IN (
      'todo', 'ready', 'queued', 'running', 'in_progress', 'review',
      'pending_review', 'blocked', 'done', 'cancelled', 'superseded', 'archived'
    )),
  -- Role accepts both kernel-native roles and the live ledger owner_role
  -- vocabulary (codex-implementer / implementer-agent / org-*) so the loader
  -- does not have to rewrite owner_role into the projection.
  role TEXT NOT NULL DEFAULT 'implementer'
    CHECK (role IN (
      'manager', 'planner', 'architect', 'implementer', 'reviewer',
      'integrator', 'owner', 'codex-implementer', 'implementer-agent',
      'org-architect', 'org-planner', 'org-reviewer', 'system'
    )),
  priority TEXT NOT NULL DEFAULT 'P2'
    CHECK (priority IN ('P0', 'P1', 'P2', 'P3')),
  assigned_worker_id TEXT REFERENCES workers(id) ON DELETE SET NULL,
  branch TEXT,
  allowed_paths_json TEXT NOT NULL DEFAULT '[]'
    CHECK (json_valid(allowed_paths_json)),
  acceptance_criteria_json TEXT NOT NULL DEFAULT '[]'
    CHECK (json_valid(acceptance_criteria_json)),
  dependencies_json TEXT NOT NULL DEFAULT '[]'
    CHECK (json_valid(dependencies_json)),
  metadata_json TEXT NOT NULL DEFAULT '{}'
    CHECK (json_valid(metadata_json)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  completed_at TEXT
);

CREATE TABLE IF NOT EXISTS leases (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  worker_id TEXT REFERENCES workers(id) ON DELETE SET NULL,
  resource TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'released', 'expired', 'revoked')),
  acquired_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  expires_at TEXT NOT NULL,
  released_at TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}'
    CHECK (json_valid(metadata_json))
);

CREATE TABLE IF NOT EXISTS runs (
  id TEXT PRIMARY KEY,
  task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
  worker_id TEXT REFERENCES workers(id) ON DELETE SET NULL,
  role TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'running'
    CHECK (status IN ('running', 'completed', 'blocked', 'failed', 'cancelled')),
  command TEXT,
  started_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  finished_at TEXT,
  stdout_path TEXT,
  stderr_path TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}'
    CHECK (json_valid(metadata_json))
);

CREATE TABLE IF NOT EXISTS approvals (
  id TEXT PRIMARY KEY,
  task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
  requested_by_worker_id TEXT REFERENCES workers(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled', 'expired')),
  approver TEXT,
  decision TEXT,
  requested_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  decided_at TEXT,
  payload_json TEXT NOT NULL DEFAULT '{}'
    CHECK (json_valid(payload_json)),
  metadata_json TEXT NOT NULL DEFAULT '{}'
    CHECK (json_valid(metadata_json))
);

CREATE TABLE IF NOT EXISTS artifacts (
  id TEXT PRIMARY KEY,
  task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
  run_id TEXT REFERENCES runs(id) ON DELETE SET NULL,
  kind TEXT NOT NULL,
  path TEXT NOT NULL,
  checksum TEXT,
  content_type TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}'
    CHECK (json_valid(metadata_json)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  UNIQUE (task_id, path)
);

CREATE TABLE IF NOT EXISTS integrations (
  id TEXT PRIMARY KEY,
  provider TEXT NOT NULL,
  name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'unknown'
    CHECK (status IN ('unknown', 'available', 'degraded', 'unavailable', 'disabled')),
  config_json TEXT NOT NULL DEFAULT '{}'
    CHECK (json_valid(config_json)),
  last_checked_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  UNIQUE (provider, name)
);

CREATE TABLE IF NOT EXISTS events (
  id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,
  aggregate_type TEXT NOT NULL,
  aggregate_id TEXT NOT NULL,
  project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
  task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
  worker_id TEXT REFERENCES workers(id) ON DELETE SET NULL,
  severity TEXT NOT NULL DEFAULT 'info'
    CHECK (severity IN ('debug', 'info', 'warning', 'error', 'critical')),
  source TEXT NOT NULL DEFAULT 'orgos',
  fingerprint TEXT,
  payload_json TEXT NOT NULL DEFAULT '{}'
    CHECK (json_valid(payload_json)),
  occurred_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

-- Baseline checksums for generated view files (.ai/*.generated.*).
-- Columns match scripts/org/check-generated-checksums.py and
-- tests/kernel/test-checksum-verify.sh: the verifier does
-- `SELECT path, sha256 FROM view_checksums` and treats `path` as the
-- repo-relative generated-view path. `path` is the SSOT key, not `view_name`.
CREATE TABLE IF NOT EXISTS view_checksums (
  path TEXT PRIMARY KEY,
  sha256 TEXT NOT NULL,
  source_event_seq INTEGER NOT NULL DEFAULT 0
    CHECK (source_event_seq >= 0),
  generated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  metadata_json TEXT NOT NULL DEFAULT '{}'
    CHECK (json_valid(metadata_json))
);

CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(status);
CREATE INDEX IF NOT EXISTS idx_workers_status ON workers(status);
CREATE INDEX IF NOT EXISTS idx_tasks_project_id ON tasks(project_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_assigned_worker_id ON tasks(assigned_worker_id);
CREATE INDEX IF NOT EXISTS idx_leases_task_id ON leases(task_id);
CREATE INDEX IF NOT EXISTS idx_leases_resource_status ON leases(resource, status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_leases_one_active_resource
  ON leases(resource)
  WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_runs_task_id ON runs(task_id);
CREATE INDEX IF NOT EXISTS idx_approvals_task_id ON approvals(task_id);
CREATE INDEX IF NOT EXISTS idx_artifacts_task_id ON artifacts(task_id);
CREATE INDEX IF NOT EXISTS idx_events_occurred_at ON events(occurred_at);
CREATE INDEX IF NOT EXISTS idx_events_aggregate ON events(aggregate_type, aggregate_id);
CREATE INDEX IF NOT EXISTS idx_events_task_id ON events(task_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_events_fingerprint
  ON events(fingerprint)
  WHERE fingerprint IS NOT NULL;

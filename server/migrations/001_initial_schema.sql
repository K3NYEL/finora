BEGIN;

CREATE TABLE IF NOT EXISTS schema_migrations (
  version TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE users (
  id TEXT PRIMARY KEY CHECK (id ~ '^usr_[0-9a-fA-F]{32}$'),
  first_name TEXT NOT NULL CHECK (length(trim(first_name)) BETWEEN 1 AND 80),
  last_name TEXT NOT NULL CHECK (length(trim(last_name)) BETWEEN 1 AND 80),
  login_identifier TEXT NOT NULL,
  login_identifier_normalized TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'closed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_login_at TIMESTAMPTZ
);

CREATE TABLE accounts (
  sync_id UUID PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 120),
  type TEXT NOT NULL CHECK (length(trim(type)) BETWEEN 1 AND 40),
  initial_balance_minor BIGINT NOT NULL DEFAULT 0 CHECK (initial_balance_minor >= 0),
  currency_code CHAR(3) NOT NULL CHECK (currency_code ~ '^[A-Z]{3}$'),
  is_archived BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0),
  deleted_at TIMESTAMPTZ,
  UNIQUE (sync_id, user_id)
);
CREATE INDEX accounts_owner_updated_idx ON accounts(user_id, updated_at DESC);

CREATE TABLE categories (
  sync_id UUID PRIMARY KEY,
  user_id TEXT REFERENCES users(id) ON DELETE RESTRICT,
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 100),
  type TEXT NOT NULL CHECK (type IN ('income', 'expense')),
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  is_system BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0),
  deleted_at TIMESTAMPTZ,
  UNIQUE (sync_id, user_id),
  CHECK ((is_system AND user_id IS NULL) OR (NOT is_system AND user_id IS NOT NULL))
);
CREATE INDEX categories_owner_type_idx ON categories(user_id, type) WHERE deleted_at IS NULL;
CREATE INDEX categories_system_type_idx ON categories(type) WHERE is_system AND deleted_at IS NULL;

CREATE TABLE transactions (
  sync_id UUID PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  account_sync_id UUID NOT NULL,
  category_sync_id UUID NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('income', 'expense')),
  amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
  description TEXT NOT NULL DEFAULT '' CHECK (length(description) <= 2000),
  occurred_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0),
  deleted_at TIMESTAMPTZ,
  FOREIGN KEY (account_sync_id, user_id) REFERENCES accounts(sync_id, user_id) ON DELETE RESTRICT,
  UNIQUE (sync_id, user_id)
);
CREATE INDEX transactions_owner_date_idx ON transactions(user_id, occurred_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX transactions_owner_account_date_idx ON transactions(user_id, account_sync_id, occurred_at DESC) WHERE deleted_at IS NULL;

CREATE TABLE transfers (
  sync_id UUID PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  source_account_sync_id UUID NOT NULL,
  destination_account_sync_id UUID NOT NULL,
  amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
  description TEXT NOT NULL DEFAULT '' CHECK (length(description) <= 2000),
  occurred_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0),
  deleted_at TIMESTAMPTZ,
  CHECK (source_account_sync_id <> destination_account_sync_id),
  FOREIGN KEY (source_account_sync_id, user_id) REFERENCES accounts(sync_id, user_id) ON DELETE RESTRICT,
  FOREIGN KEY (destination_account_sync_id, user_id) REFERENCES accounts(sync_id, user_id) ON DELETE RESTRICT,
  UNIQUE (sync_id, user_id)
);
CREATE INDEX transfers_owner_date_idx ON transfers(user_id, occurred_at DESC) WHERE deleted_at IS NULL;

CREATE TABLE refresh_sessions (
  id UUID PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  replaced_by UUID REFERENCES refresh_sessions(id) ON DELETE SET NULL,
  CHECK (expires_at > created_at)
);
CREATE INDEX refresh_sessions_user_active_idx ON refresh_sessions(user_id, expires_at) WHERE revoked_at IS NULL;

CREATE TABLE sync_operations (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  operation_id UUID NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('account', 'category', 'transaction', 'transfer')),
  entity_sync_id UUID NOT NULL,
  response JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, operation_id)
);

CREATE TABLE sync_changes (
  cursor BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('account', 'category', 'transaction', 'transfer')),
  entity_sync_id UUID NOT NULL,
  entity_version BIGINT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX sync_changes_owner_cursor_idx ON sync_changes(user_id, cursor);


CREATE TABLE backup_imports (
  id UUID PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  checksum TEXT NOT NULL CHECK (checksum ~ '^[0-9a-f]{64}
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  category_owner TEXT;
  category_system BOOLEAN;
  category_type TEXT;
BEGIN
  SELECT user_id, is_system, type
    INTO category_owner, category_system, category_type
  FROM categories
  WHERE sync_id = NEW.category_sync_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'category_not_available' USING ERRCODE = '23503';
  END IF;
  IF NOT category_system AND category_owner IS DISTINCT FROM NEW.user_id THEN
    RAISE EXCEPTION 'category_owner_mismatch' USING ERRCODE = '23514';
  END IF;
  IF category_type <> NEW.type THEN
    RAISE EXCEPTION 'category_type_mismatch' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER transactions_category_owner_guard
BEFORE INSERT OR UPDATE OF user_id, category_sync_id, type ON transactions
FOR EACH ROW EXECUTE FUNCTION finora_check_transaction_category();

CREATE OR REPLACE FUNCTION finora_check_transfer_currency()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  source_currency CHAR(3);
  destination_currency CHAR(3);
BEGIN
  SELECT currency_code INTO source_currency
    FROM accounts
    WHERE sync_id = NEW.source_account_sync_id AND user_id = NEW.user_id AND deleted_at IS NULL;
  SELECT currency_code INTO destination_currency
    FROM accounts
    WHERE sync_id = NEW.destination_account_sync_id AND user_id = NEW.user_id AND deleted_at IS NULL;
  IF source_currency IS NULL OR destination_currency IS NULL THEN
    RAISE EXCEPTION 'transfer_account_not_available' USING ERRCODE = '23503';
  END IF;
  IF source_currency <> destination_currency THEN
    RAISE EXCEPTION 'transfer_currency_mismatch' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER transfers_currency_guard
BEFORE INSERT OR UPDATE OF user_id, source_account_sync_id, destination_account_sync_id ON transfers
FOR EACH ROW EXECUTE FUNCTION finora_check_transfer_currency();

INSERT INTO categories (sync_id, user_id, name, type, is_default, is_system) VALUES
  ('00000000-0000-4000-8000-000000000001', NULL, 'Alimentación', 'expense', TRUE, TRUE),
  ('00000000-0000-4000-8000-000000000002', NULL, 'Transporte', 'expense', TRUE, TRUE),
  ('00000000-0000-4000-8000-000000000003', NULL, 'Vivienda', 'expense', TRUE, TRUE),
  ('00000000-0000-4000-8000-000000000004', NULL, 'Salud', 'expense', TRUE, TRUE),
  ('00000000-0000-4000-8000-000000000005', NULL, 'Ocio', 'expense', TRUE, TRUE),
  ('00000000-0000-4000-8000-000000000006', NULL, 'Otros gastos', 'expense', TRUE, TRUE),
  ('00000000-0000-4000-8000-000000000007', NULL, 'Salario', 'income', TRUE, TRUE),
  ('00000000-0000-4000-8000-000000000008', NULL, 'Otros ingresos', 'income', TRUE, TRUE);

INSERT INTO schema_migrations(version) VALUES ('001_initial_schema');

COMMIT;
),
  counts JSONB NOT NULL,
  imported_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, checksum)
);

CREATE TABLE local_entity_mappings (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('account', 'category', 'transaction', 'transfer')),
  local_id TEXT NOT NULL,
  sync_id UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, entity_type, local_id),
  UNIQUE (user_id, entity_type, sync_id)
);
CREATE INDEX local_entity_mappings_sync_idx ON local_entity_mappings(user_id, sync_id);

CREATE OR REPLACE FUNCTION finora_check_transaction_category()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  category_owner TEXT;
  category_system BOOLEAN;
  category_type TEXT;
BEGIN
  SELECT user_id, is_system, type
    INTO category_owner, category_system, category_type
  FROM categories
  WHERE sync_id = NEW.category_sync_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'category_not_available' USING ERRCODE = '23503';
  END IF;
  IF NOT category_system AND category_owner IS DISTINCT FROM NEW.user_id THEN
    RAISE EXCEPTION 'category_owner_mismatch' USING ERRCODE = '23514';
  END IF;
  IF category_type <> NEW.type THEN
    RAISE EXCEPTION 'category_type_mismatch' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER transactions_category_owner_guard
BEFORE INSERT OR UPDATE OF user_id, category_sync_id, type ON transactions
FOR EACH ROW EXECUTE FUNCTION finora_check_transaction_category();

CREATE OR REPLACE FUNCTION finora_check_transfer_currency()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  source_currency CHAR(3);
  destination_currency CHAR(3);
BEGIN
  SELECT currency_code INTO source_currency
    FROM accounts
    WHERE sync_id = NEW.source_account_sync_id AND user_id = NEW.user_id AND deleted_at IS NULL;
  SELECT currency_code INTO destination_currency
    FROM accounts
    WHERE sync_id = NEW.destination_account_sync_id AND user_id = NEW.user_id AND deleted_at IS NULL;
  IF source_currency IS NULL OR destination_currency IS NULL THEN
    RAISE EXCEPTION 'transfer_account_not_available' USING ERRCODE = '23503';
  END IF;
  IF source_currency <> destination_currency THEN
    RAISE EXCEPTION 'transfer_currency_mismatch' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER transfers_currency_guard
BEFORE INSERT OR UPDATE OF user_id, source_account_sync_id, destination_account_sync_id ON transfers
FOR EACH ROW EXECUTE FUNCTION finora_check_transfer_currency();

INSERT INTO categories (sync_id, user_id, name, type, is_default, is_system) VALUES
  ('00000000-0000-4000-8000-000000000001', NULL, 'Alimentación', 'expense', TRUE, TRUE),
  ('00000000-0000-4000-8000-000000000002', NULL, 'Transporte', 'expense', TRUE, TRUE),
  ('00000000-0000-4000-8000-000000000003', NULL, 'Vivienda', 'expense', TRUE, TRUE),
  ('00000000-0000-4000-8000-000000000004', NULL, 'Salud', 'expense', TRUE, TRUE),
  ('00000000-0000-4000-8000-000000000005', NULL, 'Ocio', 'expense', TRUE, TRUE),
  ('00000000-0000-4000-8000-000000000006', NULL, 'Otros gastos', 'expense', TRUE, TRUE),
  ('00000000-0000-4000-8000-000000000007', NULL, 'Salario', 'income', TRUE, TRUE),
  ('00000000-0000-4000-8000-000000000008', NULL, 'Otros ingresos', 'income', TRUE, TRUE);

INSERT INTO schema_migrations(version) VALUES ('001_initial_schema');

COMMIT;

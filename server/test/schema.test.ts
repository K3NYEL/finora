import 'dotenv/config';
import { after, test } from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';

const { Pool } = pg;
const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error('DATABASE_URL is required for schema integration tests');
const pool = new Pool({ connectionString });

after(async () => {
  await pool.end();
});

test('migration installs expected tables and shared categories', async () => {
  const tables = await pool.query<{ table_name: string }>(
    `SELECT table_name FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name = ANY($1::text[])`,
    [['users', 'accounts', 'categories', 'transactions', 'transfers', 'sync_operations', 'sync_changes', 'refresh_sessions']],
  );
  assert.equal(tables.rowCount, 8);

  const categories = await pool.query<{ count: string }>(
    'SELECT count(*)::text AS count FROM categories WHERE is_system = true AND user_id IS NULL AND deleted_at IS NULL',
  );
  assert.equal(categories.rows[0]?.count, '8');

  const guards = await pool.query<{ tgname: string }>(
    `SELECT tgname FROM pg_trigger
     WHERE NOT tgisinternal AND tgname = ANY($1::text[])`,
    [['transactions_category_owner_guard', 'transfers_currency_guard']],
  );
  assert.equal(guards.rowCount, 2);
});

test('user IDs and login identifiers have database-level uniqueness', async () => {
  const constraints = await pool.query<{ conname: string }>(
    `SELECT conname FROM pg_constraint
     WHERE conrelid = 'users'::regclass AND contype IN ('p', 'u', 'c')`,
  );
  assert.ok(constraints.rows.some((row) => row.conname === 'users_pkey'));
  assert.ok(constraints.rows.some((row) => row.conname.includes('login_identifier_normalized')));
  assert.ok(constraints.rows.some((row) => row.conname.includes('id_check')));
});

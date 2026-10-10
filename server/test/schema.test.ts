import 'dotenv/config';
import { after, test } from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';
import { randomUUID } from 'node:crypto';

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
    [['users', 'accounts', 'categories', 'transactions', 'transfers', 'sync_operations', 'sync_changes', 'refresh_sessions', 'backup_imports', 'local_entity_mappings']],
  );
  assert.equal(tables.rowCount, 10);

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

test('database prevents cross-user account and private-category references', async () => {
  const client = await pool.connect();
  const userA = `usr_${randomUUID().replaceAll('-', '')}`;
  const userB = `usr_${randomUUID().replaceAll('-', '')}`;
  const accountA = randomUUID();
  const accountB = randomUUID();
  const privateCategoryA = randomUUID();
  try {
    await client.query('BEGIN');
    await client.query(
      `INSERT INTO users (id, first_name, last_name, login_identifier, login_identifier_normalized, password_hash)
       VALUES ($1, 'Test', 'Owner A', $2, $2, 'test-hash'), ($3, 'Test', 'Owner B', $4, $4, 'test-hash')`,
      [userA, `a-${userA}@test.invalid`, userB, `b-${userB}@test.invalid`],
    );
    await client.query(
      `INSERT INTO accounts (sync_id, user_id, name, type, currency_code)
       VALUES ($1, $2, 'Account A', 'cash', 'DOP'), ($3, $4, 'Account B', 'cash', 'DOP')`,
      [accountA, userA, accountB, userB],
    );
    await client.query(
      `INSERT INTO categories (sync_id, user_id, name, type)
       VALUES ($1, $2, 'Private A', 'expense')`,
      [privateCategoryA, userA],
    );

    await client.query('SAVEPOINT cross_owner_check');
    await assert.rejects(client.query(
      `INSERT INTO transactions (sync_id, user_id, account_sync_id, category_sync_id, type, amount_minor, occurred_at)
       VALUES ($1, $2, $3, '00000000-0000-4000-8000-000000000006', 'expense', 100, now())`,
      [randomUUID(), userB, accountA],
    ));
    await client.query('ROLLBACK TO SAVEPOINT cross_owner_check');

    await client.query('SAVEPOINT cross_category_check');
    await assert.rejects(client.query(
      `INSERT INTO transactions (sync_id, user_id, account_sync_id, category_sync_id, type, amount_minor, occurred_at)
       VALUES ($1, $2, $3, $4, 'expense', 100, now())`,
      [randomUUID(), userB, accountB, privateCategoryA],
    ));
    await client.query('ROLLBACK TO SAVEPOINT cross_category_check');
    await client.query('ROLLBACK');
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
});

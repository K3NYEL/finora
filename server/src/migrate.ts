import 'dotenv/config';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pool } from './db.js';

const client = await pool.connect();

try {
  await client.query('SELECT pg_advisory_lock($1)', [7219042601]);
  const exists = await client.query<{ exists: boolean }>(
    "SELECT to_regclass('public.schema_migrations') IS NOT NULL AS exists",
  );

  if (exists.rows[0]?.exists) {
    const applied = await client.query<{ version: string }>(
      'SELECT version FROM schema_migrations',
    );
    if (applied.rows.some((row) => row.version === '001_initial_schema')) {
      console.log('No pending PostgreSQL migrations.');
      process.exitCode = 0;
    } else {
      const sql = await readFile(join(process.cwd(), 'migrations', '001_initial_schema.sql'), 'utf8');
      await client.query(sql);
      console.log('Applied migration 001_initial_schema.');
    }
  } else {
    const sql = await readFile(join(process.cwd(), 'migrations', '001_initial_schema.sql'), 'utf8');
    await client.query(sql);
    console.log('Applied migration 001_initial_schema.');
  }
} catch (error) {
  console.error('PostgreSQL migration failed:', error instanceof Error ? error.message : 'unknown error');
  process.exitCode = 1;
} finally {
  try {
    await client.query('SELECT pg_advisory_unlock($1)', [7219042601]);
  } catch {
    // The connection may already have been closed by PostgreSQL.
  }
  client.release();
  await pool.end();
}

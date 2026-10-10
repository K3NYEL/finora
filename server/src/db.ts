import 'dotenv/config';
import pg from 'pg';

const { Pool } = pg;
const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  throw new Error('DATABASE_URL is required');
}

const useTls = process.env.DATABASE_SSL === 'true';
if (process.env.NODE_ENV === 'production' && !useTls) {
  throw new Error('DATABASE_SSL=true is required in production');
}

function connectionStringWithoutTlsOverrides(value: string): string {
  // Keep TLS policy controlled by this module. Some PostgreSQL URL parameters
  // can override the explicit ssl object passed to node-postgres.
  const url = new URL(value);
  for (const parameter of ['sslmode', 'ssl', 'sslrootcert', 'sslcert', 'sslkey']) {
    url.searchParams.delete(parameter);
  }
  return url.toString();
}

export const pool = new Pool({
  connectionString: useTls ? connectionStringWithoutTlsOverrides(connectionString) : connectionString,
  max: Number(process.env.PG_POOL_MAX ?? 5),
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000,
  ...(useTls ? { ssl: { rejectUnauthorized: true } } : {}),
});

pool.on('error', (error) => {
  // Do not print query parameters or credentials.
  console.error('Unexpected PostgreSQL pool error', error.message);
});

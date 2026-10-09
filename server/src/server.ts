import 'dotenv/config';
import Fastify, { type FastifyRequest } from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import argon2 from 'argon2';
import { SignJWT, jwtVerify } from 'jose';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { pool } from './db.js';

const app = Fastify({
  logger: {
    redact: ['req.headers.authorization', 'req.headers.cookie', 'req.body.password', 'req.body.passwordConfirmation'],
  },
  bodyLimit: 32 * 1024,
  trustProxy: process.env.TRUST_PROXY === 'true',
});

const jwtSecretText = process.env.JWT_SECRET;
if (!jwtSecretText || Buffer.byteLength(jwtSecretText) < 32) {
  throw new Error('JWT_SECRET must contain at least 32 bytes');
}
const jwtSecret = new TextEncoder().encode(jwtSecretText);
const accessTtl = Number(process.env.ACCESS_TOKEN_TTL_SECONDS ?? 900);
if (!Number.isInteger(accessTtl) || accessTtl < 60 || accessTtl > 3600) {
  throw new Error('ACCESS_TOKEN_TTL_SECONDS must be between 60 and 3600');
}

const origins = (process.env.CORS_ORIGINS ?? 'http://localhost:5173')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

await app.register(helmet);
await app.register(cors, {
  origin: (origin, callback) => {
    if (!origin || origins.includes(origin)) return callback(null, true);
    return callback(new Error('Origin not allowed'), false);
  },
  methods: ['GET', 'POST', 'OPTIONS'],
});
await app.register(rateLimit, { max: 100, timeWindow: '1 minute' });

const registerSchema = z.object({
  firstName: z.string().trim().min(1).max(80),
  lastName: z.string().trim().min(1).max(80),
  loginIdentifier: z.string().trim().min(3).max(254).regex(/^[^\s]+$/),
  password: z.string().min(12).max(128),
  passwordConfirmation: z.string().min(12).max(128),
}).strict().refine((value) => value.password === value.passwordConfirmation, {
  path: ['passwordConfirmation'],
  message: 'Las contraseñas no coinciden',
});

const loginSchema = z.object({
  loginIdentifier: z.string().trim().min(3).max(254),
  password: z.string().min(1).max(128),
}).strict();

type AuthenticatedRequest = FastifyRequest & { userId?: string };

async function issueAccessToken(userId: string): Promise<string> {
  return new SignJWT({ typ: 'access' })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(userId)
    .setIssuer('finora-api')
    .setAudience('finora-client')
    .setIssuedAt()
    .setExpirationTime(Math.floor(Date.now() / 1000) + accessTtl)
    .sign(jwtSecret);
}

async function authenticate(request: AuthenticatedRequest): Promise<void> {
  const header = request.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    throw Object.assign(new Error('No autenticado'), { statusCode: 401 });
  }
  try {
    const { payload } = await jwtVerify(header.slice(7), jwtSecret, {
      algorithms: ['HS256'],
      issuer: 'finora-api',
      audience: 'finora-client',
    });
    if (payload.typ !== 'access' || typeof payload.sub !== 'string') throw new Error('invalid token');
    request.userId = payload.sub;
  } catch {
    throw Object.assign(new Error('Sesión inválida o expirada'), { statusCode: 401 });
  }
}

app.get('/health', async () => ({ status: 'ok' }));

app.get('/ready', async (_request, reply) => {
  try {
    await pool.query('SELECT 1');
    return { status: 'ready', database: 'ok' };
  } catch {
    return reply.code(503).send({ status: 'unavailable' });
  }
});

app.post('/v1/auth/register', {
  config: { rateLimit: { max: 5, timeWindow: '15 minutes' } },
}, async (request, reply) => {
  const parsed = registerSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'invalid_request', details: parsed.error.issues.map(({ path, message }) => ({ path, message })) });
  }

  const { firstName, lastName, loginIdentifier, password } = parsed.data;
  const normalized = loginIdentifier.toLocaleLowerCase('en-US');
  const passwordHash = await argon2.hash(password, { type: argon2.argon2id });
  const id = `usr_${randomUUID().replaceAll('-', '')}`;

  try {
    await pool.query(
      `INSERT INTO users (id, first_name, last_name, login_identifier, login_identifier_normalized, password_hash)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [id, firstName, lastName, loginIdentifier, normalized, passwordHash],
    );
  } catch (error) {
    if (typeof error === 'object' && error !== null && 'code' in error && error.code === '23505') {
      return reply.code(409).send({ error: 'account_unavailable' });
    }
    request.log.error({ err: error }, 'Account registration failed');
    return reply.code(503).send({ error: 'service_unavailable' });
  }

  const accessToken = await issueAccessToken(id);
  return reply.code(201).send({
    user: { id, firstName, lastName, loginIdentifier },
    accessToken,
    tokenType: 'Bearer',
    expiresIn: accessTtl,
  });
});

app.post('/v1/auth/login', {
  config: { rateLimit: { max: 10, timeWindow: '15 minutes' } },
}, async (request, reply) => {
  const parsed = loginSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

  const normalized = parsed.data.loginIdentifier.toLocaleLowerCase('en-US');
  const result = await pool.query<{
    id: string; first_name: string; last_name: string; login_identifier: string;
    password_hash: string; status: string;
  }>(
    `SELECT id, first_name, last_name, login_identifier, password_hash, status
     FROM users WHERE login_identifier_normalized = $1 LIMIT 1`,
    [normalized],
  );
  const user = result.rows[0];
  const valid = user ? await argon2.verify(user.password_hash, parsed.data.password).catch(() => false) : false;
  if (!user || !valid || user.status !== 'active') {
    return reply.code(401).send({ error: 'invalid_credentials' });
  }

  await pool.query('UPDATE users SET last_login_at = now(), updated_at = now() WHERE id = $1', [user.id]);
  const accessToken = await issueAccessToken(user.id);
  return {
    user: { id: user.id, firstName: user.first_name, lastName: user.last_name, loginIdentifier: user.login_identifier },
    accessToken,
    tokenType: 'Bearer',
    expiresIn: accessTtl,
  };
});

app.get('/v1/me', { preHandler: authenticate }, async (request: AuthenticatedRequest, reply) => {
  const result = await pool.query<{
    id: string; first_name: string; last_name: string; login_identifier: string; created_at: Date;
  }>(
    `SELECT id, first_name, last_name, login_identifier, created_at
     FROM users WHERE id = $1 AND status = 'active'`,
    [request.userId],
  );
  const user = result.rows[0];
  if (!user) return reply.code(401).send({ error: 'invalid_session' });
  return {
    id: user.id,
    firstName: user.first_name,
    lastName: user.last_name,
    loginIdentifier: user.login_identifier,
    createdAt: user.created_at,
  };
});


const accountSchema = z.object({
  name: z.string().trim().min(1).max(120),
  type: z.string().trim().min(1).max(40),
  initialBalanceMinor: z.number().int().safe().nonnegative(),
  currencyCode: z.string().regex(/^[A-Za-z]{3}$/).transform((value) => value.toUpperCase()),
}).strict();

const categorySchema = z.object({
  name: z.string().trim().min(1).max(100),
  type: z.enum(['income', 'expense']),
}).strict();

const transactionSchema = z.object({
  accountSyncId: z.string().uuid(),
  categorySyncId: z.string().uuid(),
  type: z.enum(['income', 'expense']),
  amountMinor: z.number().int().safe().positive(),
  description: z.string().max(2000).optional().default(''),
  occurredAt: z.string().datetime({ offset: true }),
}).strict();

const transferSchema = z.object({
  sourceAccountSyncId: z.string().uuid(),
  destinationAccountSyncId: z.string().uuid(),
  amountMinor: z.number().int().safe().positive(),
  description: z.string().max(2000).optional().default(''),
  occurredAt: z.string().datetime({ offset: true }),
}).strict();

app.get('/v1/accounts', { preHandler: authenticate }, async (request: AuthenticatedRequest) => {
  const result = await pool.query(
    `SELECT sync_id AS "syncId", name, type, initial_balance_minor AS "initialBalanceMinor",
            currency_code AS "currencyCode", is_archived AS "isArchived",
            created_at AS "createdAt", updated_at AS "updatedAt", version
     FROM accounts WHERE user_id = $1 AND deleted_at IS NULL ORDER BY created_at, sync_id`,
    [request.userId],
  );
  return { accounts: result.rows };
});

app.post('/v1/accounts', { preHandler: authenticate }, async (request: AuthenticatedRequest, reply) => {
  const parsed = accountSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
  const account = parsed.data;
  const result = await pool.query(
    `INSERT INTO accounts (sync_id, user_id, name, type, initial_balance_minor, currency_code)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING sync_id AS "syncId", name, type, initial_balance_minor AS "initialBalanceMinor",
               currency_code AS "currencyCode", is_archived AS "isArchived",
               created_at AS "createdAt", updated_at AS "updatedAt", version`,
    [randomUUID(), request.userId, account.name, account.type, account.initialBalanceMinor, account.currencyCode],
  );
  return reply.code(201).send(result.rows[0]);
});

app.get('/v1/categories', { preHandler: authenticate }, async (request: AuthenticatedRequest) => {
  const querySchema = z.object({ type: z.enum(['income', 'expense']).optional() }).strict();
  const parsed = querySchema.safeParse(request.query);
  if (!parsed.success) return { categories: [] };
  const result = await pool.query(
    `SELECT sync_id AS "syncId", name, type, is_default AS "isDefault", is_system AS "isSystem"
     FROM categories
     WHERE (user_id = $1 OR is_system = TRUE) AND deleted_at IS NULL
       AND ($2::text IS NULL OR type = $2)
     ORDER BY is_system DESC, name`,
    [request.userId, parsed.data.type ?? null],
  );
  return { categories: result.rows };
});

app.post('/v1/categories', { preHandler: authenticate }, async (request: AuthenticatedRequest, reply) => {
  const parsed = categorySchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
  const result = await pool.query(
    `INSERT INTO categories (sync_id, user_id, name, type)
     VALUES ($1, $2, $3, $4)
     RETURNING sync_id AS "syncId", name, type, is_default AS "isDefault", is_system AS "isSystem"`,
    [randomUUID(), request.userId, parsed.data.name, parsed.data.type],
  );
  return reply.code(201).send(result.rows[0]);
});

app.get('/v1/transactions', { preHandler: authenticate }, async (request: AuthenticatedRequest) => {
  const result = await pool.query(
    `SELECT t.sync_id AS "syncId", t.account_sync_id AS "accountSyncId",
            t.category_sync_id AS "categorySyncId", t.type, t.amount_minor AS "amountMinor",
            t.description, t.occurred_at AS "occurredAt", t.created_at AS "createdAt",
            t.updated_at AS "updatedAt", t.version
     FROM transactions t
     WHERE t.user_id = $1 AND t.deleted_at IS NULL
     ORDER BY t.occurred_at DESC LIMIT 1000`,
    [request.userId],
  );
  return { transactions: result.rows };
});

app.post('/v1/transactions', { preHandler: authenticate }, async (request: AuthenticatedRequest, reply) => {
  const parsed = transactionSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
  const transaction = parsed.data;
  try {
    const result = await pool.query(
      `INSERT INTO transactions
       (sync_id, user_id, account_sync_id, category_sync_id, type, amount_minor, description, occurred_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING sync_id AS "syncId", account_sync_id AS "accountSyncId",
                 category_sync_id AS "categorySyncId", type, amount_minor AS "amountMinor",
                 description, occurred_at AS "occurredAt", created_at AS "createdAt",
                 updated_at AS "updatedAt", version`,
      [randomUUID(), request.userId, transaction.accountSyncId, transaction.categorySyncId,
       transaction.type, transaction.amountMinor, transaction.description, transaction.occurredAt],
    );
    return reply.code(201).send(result.rows[0]);
  } catch (error) {
    if (typeof error === 'object' && error !== null && 'code' in error && ['23503', '23514'].includes(String(error.code))) {
      return reply.code(400).send({ error: 'invalid_financial_reference' });
    }
    throw error;
  }
});

app.get('/v1/transfers', { preHandler: authenticate }, async (request: AuthenticatedRequest) => {
  const result = await pool.query(
    `SELECT sync_id AS "syncId", source_account_sync_id AS "sourceAccountSyncId",
            destination_account_sync_id AS "destinationAccountSyncId",
            amount_minor AS "amountMinor", description, occurred_at AS "occurredAt",
            created_at AS "createdAt", updated_at AS "updatedAt", version
     FROM transfers WHERE user_id = $1 AND deleted_at IS NULL
     ORDER BY occurred_at DESC LIMIT 1000`,
    [request.userId],
  );
  return { transfers: result.rows };
});

app.post('/v1/transfers', { preHandler: authenticate }, async (request: AuthenticatedRequest, reply) => {
  const parsed = transferSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
  const transfer = parsed.data;
  try {
    const result = await pool.query(
      `INSERT INTO transfers
       (sync_id, user_id, source_account_sync_id, destination_account_sync_id, amount_minor, description, occurred_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING sync_id AS "syncId", source_account_sync_id AS "sourceAccountSyncId",
                 destination_account_sync_id AS "destinationAccountSyncId",
                 amount_minor AS "amountMinor", description, occurred_at AS "occurredAt",
                 created_at AS "createdAt", updated_at AS "updatedAt", version`,
      [randomUUID(), request.userId, transfer.sourceAccountSyncId, transfer.destinationAccountSyncId,
       transfer.amountMinor, transfer.description, transfer.occurredAt],
    );
    return reply.code(201).send(result.rows[0]);
  } catch (error) {
    if (typeof error === 'object' && error !== null && 'code' in error && ['23503', '23514'].includes(String(error.code))) {
      return reply.code(400).send({ error: 'invalid_financial_reference' });
    }
    throw error;
  }
});

app.setErrorHandler((error, request, reply) => {
  if (error.statusCode === 401) return reply.code(401).send({ error: 'unauthorized' });
  request.log.error({ err: error }, 'Unhandled API error');
  return reply.code(500).send({ error: 'internal_error' });
});

const host = process.env.HOST ?? '127.0.0.1';
const port = Number(process.env.PORT ?? 3000);
try {
  await app.listen({ host, port });
} catch (error) {
  app.log.error(error);
  process.exit(1);
}

const shutdown = async () => {
  await app.close();
  await pool.end();
};
process.once('SIGINT', () => void shutdown());
process.once('SIGTERM', () => void shutdown());

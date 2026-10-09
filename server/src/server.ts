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

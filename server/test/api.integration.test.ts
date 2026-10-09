import 'dotenv/config';
import { after, test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';

const port = 43187;
const baseUrl = `http://127.0.0.1:${port}`;
let server: ChildProcess | undefined;

async function waitForServer(): Promise<void> {
  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    if (server?.exitCode !== null && server?.exitCode !== undefined) {
      throw new Error(`Finora API exited before becoming ready (code ${server.exitCode})`);
    }
    try {
      const response = await fetch(`${baseUrl}/ready`);
      if (response.ok) return;
    } catch {
      // The listener may still be starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  throw new Error('Finora API did not become ready within 15 seconds');
}

after(async () => {
  if (!server || server.exitCode !== null) return;
  server.kill('SIGTERM');
  await new Promise<void>((resolve) => {
    const timeout = setTimeout(() => {
      server?.kill('SIGKILL');
      resolve();
    }, 3_000);
    server?.once('exit', () => {
      clearTimeout(timeout);
      resolve();
    });
  });
});

test('HTTP integration: auth, owner isolation, and confirmed idempotent backup import', async () => {
  if (!process.env.DATABASE_URL || !process.env.JWT_SECRET) {
    throw new Error('DATABASE_URL and JWT_SECRET are required for API integration tests');
  }

  server = spawn(process.execPath, ['dist/server.js'], {
    cwd: process.cwd(),
    env: { ...process.env, HOST: '127.0.0.1', PORT: String(port), NODE_ENV: 'test' },
    stdio: 'ignore',
  });
  await waitForServer();

  const unauthenticated = await fetch(`${baseUrl}/v1/accounts`);
  assert.equal(unauthenticated.status, 401);

  const suffix = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const register = async (identifier: string, firstName: string) => {
    const response = await fetch(`${baseUrl}/v1/auth/register`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        firstName,
        lastName: 'Integration',
        loginIdentifier: identifier,
        password: 'Finora-Test-Password-2026!',
        passwordConfirmation: 'Finora-Test-Password-2026!',
      }),
    });
    assert.equal(response.status, 201);
    return response.json() as Promise<{ user: { id: string }; accessToken: string }>;
  };

  const owner = await register(`owner-${suffix}@test.invalid`, 'Owner');
  const other = await register(`other-${suffix}@test.invalid`, 'Other');

  const me = await fetch(`${baseUrl}/v1/me`, {
    headers: { authorization: `Bearer ${owner.accessToken}` },
  });
  assert.equal(me.status, 200);
  assert.equal((await me.json() as { id: string }).id, owner.user.id);

  const createdAccount = await fetch(`${baseUrl}/v1/accounts`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${owner.accessToken}`,
    },
    body: JSON.stringify({
      name: 'Integration account',
      type: 'cash',
      initialBalanceMinor: 12345,
      currencyCode: 'DOP',
    }),
  });
  assert.equal(createdAccount.status, 201);

  const ownerAccounts = await fetch(`${baseUrl}/v1/accounts`, {
    headers: { authorization: `Bearer ${owner.accessToken}` },
  });
  assert.equal((await ownerAccounts.json() as { accounts: unknown[] }).accounts.length, 1);

  const otherAccounts = await fetch(`${baseUrl}/v1/accounts`, {
    headers: { authorization: `Bearer ${other.accessToken}` },
  });
  assert.equal((await otherAccounts.json() as { accounts: unknown[] }).accounts.length, 0);

  const backupJson = JSON.stringify({
    format: 'finora-backup',
    schema_version: 1,
    accounts: [],
    categories: [],
    transactions: [],
    transfers: [],
  });
  const preview = await fetch(`${baseUrl}/v1/import/preview`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${owner.accessToken}`,
    },
    body: JSON.stringify({ backupJson, currencyCode: 'DOP' }),
  });
  assert.equal(preview.status, 200);
  assert.equal((await preview.json() as { alreadyImported: boolean }).alreadyImported, false);

  const missingConfirmation = await fetch(`${baseUrl}/v1/import/backup`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${owner.accessToken}`,
    },
    body: JSON.stringify({ backupJson, currencyCode: 'DOP' }),
  });
  assert.equal(missingConfirmation.status, 400);

  const imported = await fetch(`${baseUrl}/v1/import/backup`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${owner.accessToken}`,
    },
    body: JSON.stringify({ backupJson, currencyCode: 'DOP', confirm: true }),
  });
  assert.equal(imported.status, 201);

  const repeatedPreview = await fetch(`${baseUrl}/v1/import/preview`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${owner.accessToken}`,
    },
    body: JSON.stringify({ backupJson, currencyCode: 'DOP' }),
  });
  assert.equal((await repeatedPreview.json() as { alreadyImported: boolean }).alreadyImported, true);

  const repeatedImport = await fetch(`${baseUrl}/v1/import/backup`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${owner.accessToken}`,
    },
    body: JSON.stringify({ backupJson, currencyCode: 'DOP', confirm: true }),
  });
  assert.equal(repeatedImport.status, 409);
});

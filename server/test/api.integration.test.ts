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

  // Representative SQLite backup: two accounts, income/expense categories,
  // linked transactions, and a transfer between the accounts.
  const backupJson = JSON.stringify({
    format: 'finora-backup',
    schema_version: 1,
    accounts: [
      {
        id: 101,
        name: 'Migration checking',
        type: 'bank',
        initial_balance: 125.5,
        initial_balance_minor: 12550,
        created_at: '2026-01-02T12:00:00.000Z',
        is_archived: 0,
      },
      {
        id: 102,
        name: 'Migration cash',
        type: 'cash',
        initial_balance: 40,
        initial_balance_minor: 4000,
        created_at: '2026-01-03T12:00:00.000Z',
        is_archived: 1,
      },
    ],
    categories: [
      { id: 201, name: 'Migration salary', type: 'income' },
      { id: 202, name: 'Migration groceries', type: 'expense' },
    ],
    transactions: [
      {
        id: 301,
        account_id: 101,
        category_id: 201,
        type: 'income',
        amount: 25.5,
        amount_minor: 2550,
        description: 'Migration test salary',
        date: '2026-01-04T09:30:00.000Z',
        created_at: '2026-01-04T09:31:00.000Z',
      },
      {
        id: 302,
        account_id: 102,
        category_id: 202,
        type: 'expense',
        amount: 10.25,
        amount_minor: 1025,
        description: 'Migration test groceries',
        date: '2026-01-05T14:15:00.000Z',
        created_at: '2026-01-05T14:16:00.000Z',
      },
    ],
    transfers: [
      {
        id: 401,
        source_account_id: 101,
        destination_account_id: 102,
        amount: 15,
        amount_minor: 1500,
        description: 'Migration test transfer',
        date: '2026-01-06T10:00:00.000Z',
        created_at: '2026-01-06T10:01:00.000Z',
      },
    ],
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
  const importResult = await imported.json() as {
    imported: boolean;
    counts: { accounts: number; categories: number; transactions: number; transfers: number };
  };
  assert.equal(importResult.imported, true);
  assert.deepEqual(importResult.counts, {
    accounts: 2,
    categories: 2,
    transactions: 2,
    transfers: 1,
  });

  const importedAccountsResponse = await fetch(`${baseUrl}/v1/accounts`, {
    headers: { authorization: `Bearer ${owner.accessToken}` },
  });
  const importedAccounts = (await importedAccountsResponse.json() as {
    accounts: Array<{ name: string; initialBalanceMinor: number; currencyCode: string; isArchived: boolean }>;
  }).accounts;
  assert.equal(importedAccountsResponse.status, 200);
  assert.equal(importedAccounts.length, 3); // Original account plus two imported accounts.
  assert.deepEqual(
    importedAccounts.filter((account) => account.name.startsWith('Migration ')).map((account) => ({
      name: account.name,
      initialBalanceMinor: account.initialBalanceMinor,
      currencyCode: account.currencyCode,
      isArchived: account.isArchived,
    })).sort((a, b) => a.name.localeCompare(b.name)),
    [
      { name: 'Migration cash', initialBalanceMinor: 4000, currencyCode: 'DOP', isArchived: true },
      { name: 'Migration checking', initialBalanceMinor: 12550, currencyCode: 'DOP', isArchived: false },
    ],
  );

  const importedCategoriesResponse = await fetch(`${baseUrl}/v1/categories`, {
    headers: { authorization: `Bearer ${owner.accessToken}` },
  });
  const importedCategories = (await importedCategoriesResponse.json() as {
    categories: Array<{ name: string; type: string }>;
  }).categories.filter((category) => category.name.startsWith('Migration '));
  assert.equal(importedCategoriesResponse.status, 200);
  assert.deepEqual(importedCategories.map((category) => ({ name: category.name, type: category.type }))
    .sort((a, b) => a.name.localeCompare(b.name)), [
    { name: 'Migration groceries', type: 'expense' },
    { name: 'Migration salary', type: 'income' },
  ]);

  const importedTransactionsResponse = await fetch(`${baseUrl}/v1/transactions`, {
    headers: { authorization: `Bearer ${owner.accessToken}` },
  });
  const importedTransactions = (await importedTransactionsResponse.json() as {
    transactions: Array<{ amountMinor: number; description: string; type: string }>;
  }).transactions;
  assert.equal(importedTransactionsResponse.status, 200);
  assert.deepEqual(importedTransactions.map((transaction) => ({
    amountMinor: transaction.amountMinor,
    description: transaction.description,
    type: transaction.type,
  })).sort((a, b) => a.description.localeCompare(b.description)), [
    { amountMinor: 1025, description: 'Migration test groceries', type: 'expense' },
    { amountMinor: 2550, description: 'Migration test salary', type: 'income' },
  ]);

  const importedTransfersResponse = await fetch(`${baseUrl}/v1/transfers`, {
    headers: { authorization: `Bearer ${owner.accessToken}` },
  });
  const importedTransfers = (await importedTransfersResponse.json() as {
    transfers: Array<{ amountMinor: number; description: string }>;
  }).transfers;
  assert.equal(importedTransfersResponse.status, 200);
  assert.deepEqual(importedTransfers.map((transfer) => ({
    amountMinor: transfer.amountMinor,
    description: transfer.description,
  })), [{ amountMinor: 1500, description: 'Migration test transfer' }]);

  // A structurally valid backup with a broken relationship must be rejected before writing.
  const invalidBackupJson = JSON.stringify({
    format: 'finora-backup',
    schema_version: 1,
    accounts: [],
    categories: [],
    transactions: [{
      id: 999, account_id: 777, category_id: 888, type: 'income',
      amount: 1, amount_minor: 100, description: 'Invalid relationship',
      date: '2026-01-07T10:00:00.000Z',
    }],
    transfers: [],
  });
  const invalidImport = await fetch(`${baseUrl}/v1/import/backup`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${owner.accessToken}`,
    },
    body: JSON.stringify({ backupJson: invalidBackupJson, currencyCode: 'DOP', confirm: true }),
  });
  assert.equal(invalidImport.status, 400);

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

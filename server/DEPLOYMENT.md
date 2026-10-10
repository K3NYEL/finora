# Finora API deployment

This API is a separate service from the Flutter app. Keep the Flutter SQLite database as the local source of truth until remote account flows and backup import have been tested end to end.

## Required environment variables

Configure these in the hosting provider's secret/environment settings, not in Git:

- NODE_ENV=production
- HOST=0.0.0.0
- PORT: use the port supplied by the hosting provider
- DATABASE_URL: Neon PostgreSQL connection URI (never commit or share it)
- DATABASE_SSL=true: enforce TLS with certificate verification
- JWT_SECRET: a unique random secret of at least 32 bytes
- CORS_ORIGINS: comma-separated exact origins that are allowed to call the API, with no trailing slash
- PG_POOL_MAX=5: tune to the database/provider connection limit

Do not put DATABASE_URL or JWT_SECRET in Flutter --dart-define, GitHub Pages, source files, issue comments, or logs.

## Build and run

Use Node.js 22 or newer and the server directory as the service root:

```sh
npm ci
npm run build
npm start
```

Health endpoints:

- GET /health checks that the process is running.
- GET /ready checks that PostgreSQL can answer a simple query.

## First database migration

Only after checking that the Neon project/database is the intended empty target, configure DATABASE_URL and DATABASE_SSL=true in a trusted local shell or the host's secret settings, then run:

```sh
npm run migrate
```

The migration creates the initial schema. Do not run it against a database containing valuable data unless the migration has been reviewed and a backup is available. Never paste the connection URI into chat or commit it to the repository.

## Before enabling remote use

1. Deploy the API with secrets configured.
2. Verify /health and /ready over HTTPS.
3. Register a test account and test login using dummy data.
4. Test account/category/transaction/transfer ownership boundaries.
5. Export a real Finora backup from a test profile and test preview/import, including repeated import and invalid backup cases.
6. Only then configure the Flutter client with --dart-define=FINORA_API_BASE_URL=https://your-api-host.

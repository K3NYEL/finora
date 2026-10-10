# Finora DataBase — starter

Standalone service scaffold for the future Finora DataBase repository. This directory is staged in the Finora integration PR only because repository-creation permissions are not available through the connected GitHub tools. Move its contents into a dedicated private repository before deployment.

## Stack
- Node.js 22+
- TypeScript
- Fastify
- PostgreSQL will be added only with a reviewed migration and least-privilege credentials.

## Run locally
1. Install Node.js 22 or newer.
2. Copy `.env.example` to `.env` and review each value.
3. Run `npm install`.
4. Run `npm run dev`.
5. Check `http://127.0.0.1:3000/api/v1/health`.

The initial service exposes only a health endpoint. Authentication, accounts, database access, and financial sync are deliberately not implemented yet.

## Safety baseline
- Do not add real financial records, tokens, credentials, private keys, database files, or production environment files to Git.
- Bind to loopback by default for local development.
- Configure HTTPS at the production ingress before exposing the service.
- CORS is deny-by-default unless an explicit origin is configured.
- Health output contains no environment details or private data.
- This scaffold is not production-ready and must not be deployed with user data.

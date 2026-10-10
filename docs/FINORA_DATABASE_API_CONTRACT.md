# Finora DataBase — API contract draft

This document is the initial integration contract between the Flutter app and the separate Finora DataBase service. It is a proposal, not a claim that a server is already deployed.

## Architecture direction

- Backend: Node.js + TypeScript + Fastify.
- Web interface: React + TypeScript + Vite.
- Database: PostgreSQL, preserving the existing migration direction. Do not expose PostgreSQL directly to the public Internet.
- Hosting target: keep the first development path compatible with a $0 budget; verify current provider limits before deployment.
- Visual design: independent from the Finora finance app. Use a GitHub-inspired dark interface: charcoal backgrounds, restrained borders, clear typography, blue/green status accents, compact navigation, accessible contrast, and responsive layouts.
- Initial web pages: public presentation home, operational dashboard, settings panel, and API documentation. Dashboard metrics must come from real service telemetry; use clearly marked placeholders until available, never fabricated live metrics.

## Principles

- Finora remains offline-first. Local SQLite data remains the source of truth until explicit sync is designed and enabled.
- Never send finance records to an unconfigured endpoint.
- Production traffic must use HTTPS. Local HTTP is allowed only for development hosts.
- Secrets, database files, signing keys, tokens, and real financial data must never be committed to Git.
- The server must authenticate each request, authorize access per user, validate input, rate-limit sensitive endpoints, and avoid logging credentials or financial payloads.
- Use parameterized SQL queries and least-privilege database credentials.
- Do not enable cross-device sync until account linking, conflict resolution, deletion semantics, and backup/restore behavior are specified and tested.

## Starter scaffold status

A minimal Node.js + TypeScript + Fastify scaffold is staged under `finora-database-starter/` in the current integration branch. It currently provides only a rate-limited health endpoint, generic errors, security headers, request-size/time limits, redacted logs, and an explicit CORS allowlist. It has no database, authentication, account routes, or financial sync.

This folder is temporary staging inside the Finora integration PR because the connected GitHub tools cannot create a new repository. Before deployment, move the folder contents into a dedicated private repository named `Finora-DataBase`. Do not deploy this scaffold or treat it as production-ready.

## Proposed first endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| GET | /api/v1/health | Public liveness check; no private data |
| POST | /api/v1/auth/register | Create an online account after the auth design is approved |
| POST | /api/v1/auth/login | Authenticate and issue short-lived access credentials |
| POST | /api/v1/auth/refresh | Rotate refresh credentials securely |
| POST | /api/v1/auth/logout | Revoke the current refresh session |
| GET | /api/v1/me | Return the authenticated account profile |

Financial synchronization endpoints are intentionally not specified as ready to use. We must design versioned sync payloads, record ownership, idempotency, conflict resolution and deletion/tombstone handling before adding them.

## Response format

Successful JSON responses should be objects. Errors should use a consistent shape such as `{"error":{"code":"VALIDATION_ERROR","message":"Readable message"}}`. The Flutter client accepts this nested shape and a legacy top-level `message` string. Never return stack traces or SQL details.

## Flutter configuration

The client reads FINORA_API_BASE_URL at build time, for example:

- Development emulator: `flutter run --dart-define=FINORA_API_BASE_URL=http://10.0.2.2:3000`
- Production: `flutter build apk --dart-define=FINORA_API_BASE_URL=https://api.your-domain.example`

For an Android physical device, use the development computer's reachable LAN address instead of `10.0.2.2`. Do not place credentials in `--dart-define`; values compiled into the app are not secrets. The current client is only a transport foundation; no authentication or financial data is sent automatically.

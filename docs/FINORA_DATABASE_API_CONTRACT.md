# Finora DataBase — API integration contract

This document records the **current implementation** of the Flutter client and the separate Finora DataBase API. It is not evidence that a public server has been deployed.

## Architecture and safety rules

- Flutter keeps local SQLite as the source of truth.
- No finance data is synchronized automatically. Do not enable push/pull until a reviewed coordinator handles consent, ownership, relationships, conflict resolution, deletions/tombstones, idempotency, and checkpoint persistence.
- Do not send credentials or financial records to an unconfigured endpoint.
- Production API traffic must use HTTPS. Plain HTTP is allowed only for local development hosts.
- Never commit secrets, database files, signing keys, tokens, backup payloads, or real financial data.
- The API uses Node.js 22+, TypeScript, Fastify, and SQLite. The server repository is [K3NYEL/Finora-DataBase](https://github.com/K3NYEL/Finora-DataBase).

## Actual server routes

The API README is the authoritative route inventory. The implemented route families include:

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/v1/health` | Public liveness check |
| POST | `/api/v1/auth/register` | Create remote account |
| POST | `/api/v1/auth/login` | Create authenticated session |
| GET | `/api/v1/auth/me` | Read authenticated profile |
| POST | `/api/v1/auth/logout` | Revoke current session |
| GET/POST | `/api/v1/accounts` | List/create remote accounts |
| GET/POST | `/api/v1/categories` | List/create remote categories |
| GET/POST | `/api/v1/transactions` | List/create remote transactions |
| GET/POST | `/api/v1/transfers` | List/create remote transfers |
| GET/POST | `/api/v1/budgets` | List/create remote budgets |
| GET/POST/DELETE | `/api/v1/backups[/:id]` | Manage encrypted backup blobs |
| GET | `/api/v1/notifications` | List the user's notifications |
| POST | `/api/v1/notifications/:id/read` | Mark a notification read |
| GET | `/api/v1/patches/latest` | Read the Android release manifest |

Administrative publishing endpoints require a server-side `FINORA_ADMIN_KEY`; that key must never be embedded in Flutter or shipped to a client.

## Authentication contract

The current server authentication API accepts:

- Registration/login request: `username` and `password`.
- Username: 3–32 characters; letters, digits, dot, underscore, and hyphen.
- Password: 12–128 characters.
- Session response: `accessToken`, `tokenType`, `expiresAt`, and a `user` object containing `id`, `username`, and `createdAt`.

The Flutter remote-account flow in `lib/core/network/api_client.dart` plus `lib/core/network/finora_remote_auth_api.dart` matches these routes and fields.

**Known integration blocker:** `lib/core/network/finora_api_client.dart`, used by the older optional cloud-auth path on the main login page, implements a different legacy contract (`/v1/auth/*`, `loginIdentifier`, `firstName`, and `lastName`). That contract does not match the current server. Do not use that legacy path for real remote authentication until it is removed or deliberately migrated with tests. Do not silently merge a remote identity with a local identity.

The dedicated remote-account page is a separate account-linking foundation. It saves its remote session in platform secure storage and does not upload local finance data. Its session is not proof that financial synchronization is ready.

## Flutter API URL

Set the base URL at build/run time; do not hardcode an unverified production hostname:

- Linux, when the API runs on the same computer: `flutter run --dart-define=FINORA_API_BASE_URL=http://127.0.0.1:3000`
- Android emulator: `flutter run --dart-define=FINORA_API_BASE_URL=http://10.0.2.2:3000`
- Physical Android device: use the development computer's reachable LAN address during local testing.
- Production: use the actual deployed HTTPS origin only after deployment and security review.

The API is not confirmed as publicly deployed. Without a configured reachable endpoint, remote authentication and health checks must remain unavailable; local SQLite use must continue normally.

## Health-check procedure

Start the server in its own repository using Node.js 22+:

```bash
npm ci
npm run dev
```

Then check:

```bash
curl http://127.0.0.1:3000/api/v1/health
```

Expected response:

```json
{"status":"ok","service":"finora-database-api"}
```

This verifies liveness only. It does not verify authentication, device connectivity, encrypted backup/restore, or sync correctness.

## Encrypted backups

The server backup vault accepts opaque encrypted bytes, not plaintext financial JSON or raw SQLite files. The client must implement and test encryption, key handling, preview, restore validation, and explicit user consent before using these endpoints. Server-side size/checksum checks do not prove that a client encrypted the payload.

## Validation and rollout gates

Before the integration is marked ready:

1. Reconcile or remove the legacy `finora_api_client.dart` authentication contract.
2. Keep one canonical transport and consistent API base-URL/path handling.
3. Add contract tests for health, register, login, profile, logout, and error responses.
4. Pass `flutter analyze`, `flutter test`, Android build validation, and the backend's `npm test`, `npm run typecheck`, and `npm run build`.
5. Validate the API against a reachable development server on Linux and Android.
6. Review consent, local/remote identity separation, and secure token expiry/revocation.
7. Only then separately implement and test financial sync and encrypted backup/restore.

Until those gates pass, keep the integration PR in draft, do not merge it as production-ready, and do not deploy the API as a public financial-data service.

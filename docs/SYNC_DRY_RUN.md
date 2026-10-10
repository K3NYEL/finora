# Finora sync dry-run preview

The cloud-account screen can run a local, count-only preview for the currently signed-in local profile.

## What it reports

- Number of owned accounts, custom categories, transactions, and transfers.
- Whether the existing sync-readiness gate passes.
- Human-readable reasons for blocked readiness.
- An eligible-record count that is forced to zero if any blocker remains.

## Privacy and safety guarantees

- The preview only reads the local SQLite database.
- It does not return amounts, descriptions, dates, account names, or other financial values.
- It does not make HTTP requests.
- It does not change `sync_state`, the cursor, `sync_status`, or any financial record.
- It does not enable synchronization or grant consent to upload.
- Even when all current readiness checks pass, the preview is not authorization to upload; the sync coordinator and explicit consent flow must be implemented and reviewed separately.

## Current limitations

This is a diagnostic dry run, not a sync implementation. Remote identity linking, local-to-remote relationship mapping, an outbox, pull reconciliation, conflict UX, backup/recovery verification, and explicit consent for financial-data transfer are still required before any upload can be enabled.

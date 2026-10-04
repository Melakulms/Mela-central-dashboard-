# Historical migration recovery archive

Recovered 4 October 2026 from the recorded SQL in the live Supabase migration registry. This directory is deliberately outside `supabase/migrations`; normal migration commands must not replay it against the existing database.

- Source project: `duizgtmbptmlbyipreqg`.
- Source PostgreSQL version: 17.6.
- Snapshot: 607 migration records; every record had SQL statements.
- Each file retains its recorded version/name and statement contents; newline/semicolon separators and an archive warning were added.
- `manifest.json` records every file's SHA-256 and byte length.
- Verify with `python scripts/verify-recovery-archive.py` from the repository root. This performs no database operations.

## Important recovery gap

**This is not a complete backup or a proven fresh-install baseline.** The earliest recorded migration already alters `public.profiles` and `public.fn_apply_coin_transaction`; their initial definitions predate this registry. Replaying the archive into an empty database will therefore not reconstruct the platform.

A current schema-only export and a separately protected data backup, including the appropriate Supabase-managed schemas, are still needed. Auth users, uploaded Storage objects, Edge Function secrets and provider configuration are not recovered by this SQL archive. Historical migrations can contain old insecure definitions and obsolete application code; the final hardened state matters, not any intermediate historical version.

## Restore acceptance procedure

1. Obtain an authorized backup/schema export through the project's administration tools. Keep user data and secrets outside the public source repository.
2. Provision an isolated staging Supabase environment compatible with PostgreSQL 17.6. Disable outbound email/payment/provider callbacks and production scheduled jobs there.
3. Restore the approved baseline/backup according to its capture point. Use recorded migration versions to identify only genuinely unapplied follow-ups; never blindly apply all archived SQL on top of a current snapshot.
4. Verify extensions, roles, grants, policies, functions, triggers, constraints, migration versions, representative row counts and Storage integrity.
5. Run the SQL authorization/ledger/assessment/video regression suites, plus staging frontend/Auth/MFA journeys. Record checksums, duration, operator, failures and recovery objectives.
6. Exercise rollback/recovery on staging and document the result before declaring restore readiness.

Status: archive integrity verified; restore NOT tested. This workspace has no PostgreSQL/Docker runtime or configured isolated staging connection. OWNER_ACTION_REQUIRED: provide secure administrative access to an isolated staging database and approved backup/export mechanism. Do not send database passwords in chat.

A known-secret-format scan found no embedded token/private-key matches. One identity-write match was reviewed: it is the partner-approval function updating the requesting account's app metadata, not an export of account records. Pattern scanning is not exhaustive historical secret certification.

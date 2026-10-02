# Central Admin API Contract Gaps

## Verified production schema

The production Supabase project currently exposes the core operational tables used by the Central Admin UI, including `profiles`, `opportunities`, `payments`, and `payout_requests`.

## Current API coverage

Implemented in `mela-admin-api`: me, dashboard, permission-filtered queues, user list/inspect/update, employer list/review, opportunity list/review, payment/payout lists, moderation list/report resolution, feature-flag list/update, commission list/inspect/cancel/summary, authorization matrix, access list, and audit list/append.

The UI now reads live operational modules, but approval controls and a dedicated dispute workflow are incomplete. Mutation and audit writes are not yet atomic. See LAUNCH_READINESS.md for verification evidence and remaining release gates.

The remaining operational UI modules require explicit API handlers before they can be considered functionally complete. Do not treat navigation or UI rendering as backend authorization.

## Safety rule

New handlers must:

1. Resolve the authenticated user server-side.
2. Resolve active admin role and permissions server-side.
3. Enforce MFA/AAL2 where required.
4. Use least-privilege permissions for each operation.
5. Return only the fields needed by the module.
6. Audit every state-changing operation with actor, target, request ID, and before/after state.
7. Never expose the service-role key to the browser.
8. Avoid direct client writes to privileged tables.

## Deployment gate

Repository changes are not production verification. Live browser and end-to-end tests remain blocked until a reachable production deployment exists.

## Transactional mutations — 2 October 2026

All six existing admin mutation actions now call `admin.apply_audited_update`, a service-only RPC that locks and compares the target record, checks actor permissions and supported fields, and commits the update and audit together. Stale records return HTTP 409. Database constraints remain authoritative. Frontend operational decision controls and disputes still require implementation.

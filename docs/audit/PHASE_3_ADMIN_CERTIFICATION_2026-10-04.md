# Central Admin certification checkpoint

Date: 4 October 2026. Decision: **NOT CERTIFIED / NO-GO for unrestricted launch**.

The owner requested work on subsequent phases. This permits engineering progress, not bypassing open security or acceptance gates. Phase 2 remains open. No bootstrap was rerun and no owner identity was replaced.

## Evidence from this checkpoint

Live registry inspection found one active super admin, zero active admins without MFA and a consumed bootstrap state. No personal identifiers were exported. Five roles and twelve permissions exist. The legacy authorization regression test failed before the repair (profile-only authority) and passed afterward.

Migration `20261004103224_restore_central_super_admin_legacy_boundary` restricts the generic override to active, registered super admins at AAL2, preserves trusted backend maintenance, and constrains active admin records to require MFA. Non-super roles retain permission-specific APIs.

The enrollment UI now uses the SDK QR data URI directly, locks duplicate submissions, handles enrollment retry, checks refresh errors and AAL2, and ignores stale callbacks. Eight new mocked SDK tests bring the admin suite to 57 passing tests. TypeScript and production build pass. Live SQL checks `admin_legacy_override.sql`, `admin_registry_authority.sql`, `atomic_admin_updates.sql` and `user_journeys.sql` passed after the migration. This does not establish real browser/authenticator acceptance.

## 23 acceptance gates

| # | Gate | Status and evidence / remaining acceptance | Owner |
|---|---|---|---|
| 1 | First super admin | Partial: bootstrap consumed; original environment-controlled activation provenance still needs review | Engineering / owner |
| 2 | RBAC matrix | Partial: five roles, twelve permissions; generic override negative tests pass; complete per-operation matrix pending | Engineering |
| 3 | MFA | Partial: active registry MFA constraint and AAL1 denial pass; real authenticator enrollment/login pending | Engineering / owner |
| 4 | Session security | Partial: refresh and stale enrollment checks tested; revocation/expiry across devices pending | Engineering |
| 5 | User management | Partial: atomic update and registry authority SQL tests pass; full operator workflow pending | Engineering |
| 6 | Identity verification | Partial: implementation inventory exists; real approve/reject/document-access journey pending | Engineering / reviewer |
| 7 | Employer verification | Partial: workflow acceptance and employer isolation pending | Engineering / reviewer |
| 8 | Mentor verification | Partial: workflow acceptance and eligibility review pending | Engineering / reviewer |
| 9 | Teacher verification | Partial: qualified educator review controls present; human qualification acceptance pending | Engineering / educator |
| 10 | Admin audit log | Partial: audited mutations present; complete event coverage/export/access review pending | Engineering |
| 11 | Security log | Partial: observability authorization tested; alert delivery/retention acceptance pending | Engineering |
| 12 | Payment management | Blocked: financial flags disabled; provider sandbox acceptance absent | Engineering / provider |
| 13 | Dispute management | Partial: full dispute/refund operator journey pending | Engineering |
| 14 | Commission settings | Partial: exact registration/premium reward cases and payout reconciliation pending | Engineering / owner |
| 15 | Content management | Partial: review workflows present; five-language publish/version/rollback acceptance pending | Engineering / reviewers |
| 16 | Moderation | Partial: proctor read authorization tested; minor-safety and report-resolution journeys pending | Engineering / safeguarding reviewer |
| 17 | Announcements | Unverified: creation, audience isolation and delivery acceptance pending | Engineering |
| 18 | Analytics | Partial: restricted observability reads tested; metric definitions and accuracy pending | Engineering |
| 19 | Realtime | Unverified: subscription isolation, reconnect and stale-session acceptance pending | Engineering |
| 20 | Consumer hosting | Partial: GitHub Pages deployed; requested Netlify/domain setup not certified | Engineering / owner |
| 21 | Admin hosting | Partial: prior Pages release succeeded; this release and real-admin browser acceptance tracked separately | Engineering |
| 22 | Backup and rollback | Blocked: 607 migration sources recovered; missing baseline and isolated restore evidence | Engineering / owner |
| 23 | Final go/no-go | NO-GO: security review, real-user acceptance, provider sandbox and restore gates remain open | Engineering / owner |

All pending items are due before their acceptance gate is certified; no invented calendar commitment is assigned. Current advisor inventory remains 94 authenticated privileged-function warnings, one intentional anonymous certificate verifier warning, eleven no-policy informational findings and leaked-password protection warning. These require disposition, not blanket dismissal.

## Owner actions

OWNER_ACTION_REQUIRED: complete real-admin acceptance using secure sign-in (never share passwords or authenticator codes in chat); configure supported leaked-password protection, public SMTP and domain; provide isolated staging/restore prerequisites and official provider sandbox access; appoint qualified verification, language, safeguarding and local legal reviewers. Existing admin access must remain intact while these are resolved.

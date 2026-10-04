# Phase 4 and 5 continuation evidence

Date: 4 October 2026. Release decision remains **NO-GO for paid/unrestricted launch**.

## Phase 4 — payments continuation

Payments remain feature-flagged OFF. No live charge, payout, provider credential or direct telebirr/CBE Birr integration was introduced.

### Checkout initiation hardening completed

The two deployed Chapa checkout initializers were missing from version control. Their maintained sources are now stored at:

- `supabase/functions/chapa-initialize/index.ts`
- `supabase/functions/mela-learning-checkout/index.ts`

Production deployments were upgraded to `chapa-initialize` v5 and `mela-learning-checkout` v3 with gateway JWT verification still enabled.

Both initializers now:

1. revalidate the bearer token through Supabase Auth instead of trusting decoded JWT claims;
2. require a complete authenticated user identity;
3. enforce configured `MELA_PAYMENT_MODE` against the Chapa secret-key environment;
4. accept only positive safe-integer minor-unit prices and ETB for these launch paths;
5. derive price from server-side course/product records rather than a client amount;
6. reuse a recent matching pending checkout rather than creating duplicates on refresh;
7. retain a bounded recent-attempt limit;
8. apply a provider initialization timeout;
9. update an attempt from `initiated` to `pending`/`failed` only conditionally, preventing a delayed initialize response from overwriting a later state;
10. include the payment environment in the transaction reference for operational clarity.

Server subscription configuration was rechecked: `normal_monthly` is 2,000 minor ETB units (20 ETB) and `premium_monthly` is 5,000 minor ETB units (50 ETB). Referral configuration is 10 ETB for the non-premium tier and 20 ETB for Premium. The active auth invitation trigger calls the tier-aware referral function. A stale service-only zero-commission helper remains unused by that trigger and must not be treated as the active referral path.

### Phase 4 still blocked

- direct telebirr and CBE Birr adapters require official merchant sandbox contracts, endpoints, signatures and credentials;
- signed provider sandbox success/failure/replay evidence is missing;
- daily settlement reconciliation is not certified;
- refund/dispute provider execution is not certified;
- payout/KYC/fraud acceptance is not certified;
- five-language payment receipt/error certification is not complete;
- payment and payout feature flags remain OFF.

## Phase 5 — core product continuation

### Mentorship rating journey completed at database/API level

Migration `20261004162514_complete_mentorship_ratings_and_wrapper_hardening.sql` adds:

- one immutable rating per completed mentorship session;
- 1–5 rating validation and a bounded optional comment;
- participant/admin-only rating reads under RLS;
- no direct browser insert/update/delete privilege;
- mentee-only rating submission after a completed session;
- aggregate `rating_average` and `rating_count` on mentor profiles;
- mentor notification when a completed session receives a rating;
- MFA-backed admin authority in mentor profile update/delete RLS policies;
- SECURITY INVOKER public wrappers for respond/schedule/cancel/complete mentorship operations while guarded private functions retain authorization checks.

Migration `20261004162626_repair_shared_role_profile_verification_guard.sql` repairs a pre-existing shared profile trigger that still called removed `public.is_admin_user()`. It now uses `private.is_admin_user()`, preventing legitimate role-profile updates from failing while preserving admin-controlled verification fields.

Rollback-only regression `supabase/tests/mentorship_ratings.sql` passed against the live schema. It proved:

- a mentee can rate their completed session;
- duplicate ratings are rejected;
- an outsider cannot read or submit the rating;
- authenticated users cannot insert directly into the ratings table;
- mentor aggregate rating/count updates correctly;
- all test fixture data is rolled back.

The Supabase security advisor was rerun after the DDL. The authenticated executable SECURITY DEFINER advisory count is now 90; the intended anonymous certificate verifier remains one warning. Eleven no-policy INFO findings remain on deliberately backend/default-deny tables, and leaked-password protection remains disabled.

### Learner UI work

The learner repository branch `codex/phase5-mentorship-ratings` / PR #25 adds:

- mentor aggregate ratings on verified mentor cards;
- a completed-session 1–5 rating form with optional comment;
- reload of the saved rating after submission;
- no duplicate rating button once a rating exists;
- a UI regression test for the rating journey.

### Phase 5 remaining work

The following prevents Phase 5 from being called fully certified even though many modules are already functional:

- complete role-by-role hosted authenticated E2E remains unrecorded;
- direct telebirr/CBE-backed paid registration/Premium activation remains disabled;
- chapter/question-bank educator certification is incomplete;
- translated assessment certification remains incomplete;
- challenges and Earn & Work stay intentionally disabled for Phase 1 until their supply/payout/moderation gates are met;
- video calls stay disabled until the production media path and safeguarding acceptance are verified;
- external email delivery requires SMTP/provider evidence;
- device/slow-network/accessibility/safeguarding human acceptance remains external work.

No disabled feature was enabled to make the progress number look better.

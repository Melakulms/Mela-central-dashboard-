# Payment engineering checkpoint

Date: 4 October 2026. Status: **IN PROGRESS — financial launch remains NO-GO**.

## Scope and actual implementation

The repository uses Chapa. It does not yet implement the requested direct telebirr or CBE Birr adapters. No provider endpoint, credential or sandbox success was invented. This release repairs an existing escrow callback; it does not activate a payment method or prove the registration/premium/referral payment journeys.

The deployed `mela-finance-callback` version 4 was recovered from Supabase because it was absent from version control. Its unchanged source is archived at `supabase/recovery/edge-functions/mela-finance-callback-v4.ts` for incident analysis. Do not redeploy this vulnerable version as an ordinary rollback. Current implementation is `supabase/functions/mela-finance-callback/index.ts`, deployed as version 5, ACTIVE, with `verify_jwt=false` and application-level webhook HMAC verification before database access. This is intentional: the provider does not send a user JWT.

## Defects repaired

| Finding | Repair | Evidence |
|---|---|---|
| Live environment accepted provider test-mode results | Require configured mode, stored attempt mode and verified provider mode to agree | Mode mismatch and cross-environment tests |
| Amounts were rounded, allowing malformed precision to appear equal | Parse positive decimal amounts with at most two decimal places and safe integer minor units | Sub-cent, exponent, null, overflow and wrong amount tests |
| Slow callback could overwrite a successful attempt with pending/failed | Conditional updates restricted to initiated/pending rows | Update filter regression test; actual concurrent database callback test still pending |
| Provider verification outage was acknowledged as handled | Return retryable 503 without financial finalization | Provider HTTP failure test |
| Callback source was not reproducible from repository | Store maintained source, config and previous deployed source | Git files and Supabase deployment response |

The callback requires a body-bound HMAC, exact reference/currency/amount/mode and a nonempty provider reference before calling the existing atomic `finalize_escrow_payment`. It rejects static secret-only signatures. Standard `x-chapa-signature` and body-signed custom `chapa-signature` are supported; actual merchant webhook configuration must be confirmed in sandbox. Terminal successful attempts are acknowledged without repeating verification, and a database idempotent result suppresses duplicate notifications. Notification delivery still lacks an outbox/retry guarantee.

## Validation and limits

- 19 new isolated callback tests pass, using mocked network/database responses and real local HMAC operations.
- Full admin suite: 76 passing tests; TypeScript and production frontend build pass. This build does not itself typecheck Deno Edge Functions; Supabase accepted the function deployment.
- Existing atomic finalizer definition reviewed: payment and escrow row locks, expected amount checks and already-success idempotency exist. No database finalizer was changed in this checkpoint.
- Read back feature gates: payments=false, payouts=false, earn_work=false, video=false.
- Deployed endpoint smoke: GET returned 405; unsigned POST returned 503 `Webhook verification unavailable`, confirming the webhook secret is not configured and the endpoint fails closed. Provider webhook secret setup and signed sandbox acceptance remain required.
- No real payment, payout, signed provider event or merchant credential was used. No load, provider sandbox, complete replay/concurrency or settlement certification is claimed.

## Required next work, in order

1. Audit all remaining checkout/verify/callback functions and recover missing deployed source. Apply equivalent amount and race protections to the separate polling route where needed; this release only changes the escrow callback.
2. Verify registration 20 ETB and Premium 50 ETB against server-side product configuration; test the 10/20 ETB referral commissions and one-reward constraints end to end.
3. Implement provider adapters only against official merchant contracts and sandbox documentation. Resolve whether each business rail is a direct integration or an explicitly approved aggregator path.
4. Complete durable webhook/event recording, daily settlement reconciliation, refund/dispute administration, payout risk controls and notification outbox. Establish behavior when retry delivery is exhausted.
5. Prove database concurrency and cross-user restrictions; run sandbox success/failure/cancellation/duplicate/amount/reference/mode cases. Test replay across both callback and manual verification.
6. Translate payment receipts and error handling across the five languages with qualified review.
7. Review pilot evidence and prior security/restore gates before considering any live financial flag.

## Owner actions and release conditions

OWNER_ACTION_REQUIRED: provide official telebirr and CBE Birr merchant sandbox onboarding, API/signature/refund/reconciliation documentation and credentials through secure configuration; confirm permitted provider path and settlement account through the provider; arrange qualified translation, local legal/refund review and controlled sandbox acceptance. Never paste merchant secrets into chat or source control. Engineering owns implementation and tests; provider/owner acceptance is due before enabling paid access. No launch date is fabricated.

## References inspected

- https://developer.chapa.co/integrations/webhooks — body-bound webhook signatures and independent verification of transaction details.
- https://supabase.com/docs/guides/functions/function-configuration — per-function JWT configuration.

These documents support integration mechanics, not proof that this merchant account is configured or certified.

## Continuation: manual verification and course payments

### Deployment drift resolved

The live `mela-finance` v5 source still contained an `isAdmin` profile-role override that had already been removed in the repository. A source comparison established the difference before deployment. Version 6 now matches the hardened implementation; tests demonstrate that an unrelated admin profile cannot act as an employer. The previous source is archived for analysis, not ordinary rollback.

### Additional fixes and evidence

- Manual escrow verification and payout verification now reject invalid decimal precision, coercions and unsafe amounts. Escrow verification compares the stored mode with configured mode before contacting the provider, then checks reference, amount, currency, provider mode and provider reference before finalization.
- Provider outages or malformed verification envelopes return retryable failure without overwriting payment state. Conditional updates restrict late pending/failed responses to unfinished attempts.
- Four course-payment endpoints were recovered, repaired, formatted and deployed. The legacy callback previously omitted mode verification. Both manual course verifiers now ask Supabase Auth to validate identity before querying user-owned payments, in addition to gateway JWT enforcement.
- Legacy course success updates use conditional writes and inspect the result. A lost race to a failed payment cannot grant enrollment or report successful finalization. Full cross-process database concurrency testing remains a separate release gate.
- Source recovery includes the two checkout initializers, which are unchanged and require further review of initiation race handling, rate limits and registration/premium/referral product alignment.

| Function | Previous version | Deployed version | Authentication |
|---|---:|---:|---|
| mela-finance | 5 | 6 | Gateway JWT plus Auth user validation and employer ownership/membership |
| chapa-verify | 3 | 4 | Gateway JWT plus Auth user validation and user-scoped payment lookup |
| chapa-callback | 5 | 6 | Body-bound HMAC |
| mela-learning-payment-verify | 2 | 3 | Gateway JWT plus Auth user validation and user-scoped payment lookup |
| mela-learning-payment-callback | 6 | 7 | Body-bound HMAC |

Validation: 164 tests across eleven suites passed, including 24 new finance tests and 64 new course-payment tests. The production frontend build passed. These counts include local synthetic fixtures; they do not certify a merchant account or real payment settlement. Supabase accepted all five deployments as ACTIVE. The finance endpoint rejected an unauthenticated POST with 401. Financial gates were read back as disabled after deployment.

### Still open

Provider-issued sandbox setup and the webhook secret are still required. Additional engineering remains: checkout initiation races, fully atomic legacy course fulfillment/reconciliation, consistent audit/event persistence, refunds/disputes, complete referral payout fraud controls, translated receipts, load testing, restore acceptance and pilot evidence. The direct telebirr/CBE Birr integrations remain absent. No real charge or transfer was initiated.

Deployed negative smoke checks also returned 401 for both manual course verifiers, and 503 (webhook secret not configured) for both course callbacks. These checks exercised rejection paths only and did not read or mutate payment records.

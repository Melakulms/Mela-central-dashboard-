# Issue #168 — financial-launch control review and owner evidence pack
**Date:** 2026-11-04 · **Scope:** MELA production payment collection, referral commissions, escrow/payout readiness.  
**Evidence level:** read-only database inspection + source review; **not** a passed real-money payment or security penetration test.  
**Parent issue:** https://github.com/Melakulms/mela-app/issues/168

## Critical launch conflict

- Production `platform_feature_flags.payments = true` and `mela_payments.settings.enabled = true`.
- Production `platform_launch_requirements('payments_provider').manual_status = 'pending'`.
- Two receiving accounts are active and have account-owner verification records. This proves that account verification is recorded; **it does not prove business registration, authorization, independent settlement or the right to collect real payments**.
- The live `mela_payments.command('catalog')` enablement predicate checks settings, flags, verified receiver, active products and reviewer; **it does not require the provider launch requirement to be complete**.
- The server `mela_payments.command('create_order')` independently checks settings and flags, but also **does not require provider launch evidence**. A UI-only fix cannot close this bypass.
- As of audit, no payment orders or referral commissions were recorded; a separate historical payout request is pending. Do not erase, approve or pay that request without reconciliation.
- `payouts=false` and `earn_work=false` in production. Keep both disabled.

**Recommended immediate owner decision:** review whether live subscription checkout should remain on before provider and legal evidence is complete. This document and its code changes do not alter any flags, payment orders or funds. Do **not** ask users to send money merely because payment account verification shows "active".

## Server-side change proposal — NOT YET APPLIED

A production migration should change **both** branches of `mela_payments.command(p_action,p_data)`, not just the learner interface. Reconstruct the latest canonical function in a reviewed migration (do not replace it with a stale copy). A privileged, immutable-in-practice checklist and an owner release review are necessary.

In the `catalog` branch, add the following **conjunctive** predicate alongside the existing account/settings/reviewer checks:

```sql
and exists (
  select 1 from public.platform_launch_requirements r
  where r.requirement_key = 'payments_provider'
    and r.manual_status = 'complete'
    and nullif(btrim(coalesce(r.evidence_note, '')), '') is not null
)
```

In the `create_order` branch, **before** user, product or account selection, reject new orders unless the same predicate is true. Missing rows, blocked, not_required or pending must all deny new orders. Check `payments`, `mela_payments.settings.enabled`, product pricing, active reviewer, provider verification and guardian clearance as now.

The **legal/business registration evidence** also needs a separate auditable gate and qualified Ethiopian review before launch; do not infer registration from the provider evidence row. If added as `wallet_business_and_legal`, require `manual_status='complete'` and documented authorization evidence in `create_order`. A new gate must not be marked complete solely by a UI checkbox.

Do **not** block `my_orders`, `submit`, `admin_queue`, `admin_record`, `admin_reject`, `admin_reverse`, or refunds for existing orders while closing *new* checkout; doing so could strand users who already paid. Preserve ordinary admin MFA/reviewer authorization.

Until those server checks are deployed and reviewed, the mismatch is **unresolved**.

## Payment and payout negative tests

| Scenario | Expected result |
| --- | --- |
| Checkout flags true but provider evidence pending | `catalog.enabled=false`; `create_order` rejects before any insert |
| Provider evidence complete but legal/business gate missing | New order rejected |
| No verified account or active reviewer | New order rejected |
| School learner without required guardian authorization | New order rejected |
| Direct authenticated RPC bypassing learner screen | New order rejected if provider/legal gate pending |
| Two duplicate incoming references | One receipt/order entitlement at most; other rejected |
| Transfer amount/recipient/currency mismatch | No entitlement, preserved audit trail |
| Disputed, reversed or refunded payment | Correct entitlement and referral compensation or reversal; no double-credit |
| Provider callback replays or retries | One authoritative settlement and an idempotency key |
| Lost MFA, inactive admin or non-reviewer | No admin payment approval or payout |
| Commission for signup without approved first payment | Zero commission payable |
| Minor attempts commission payout | Denied without specifically approved guardian flow |
| Pending payout during freeze | Remains pending; never auto-marked paid |
| Payout destination changed | Old independent verification invalidated; new proof required |
| Signed-in user A requests user B's ledger | Denied by RLS and function ownership checks |
| Android PWA reload/offline | No cached payment details exposed to another user |

**Tests are required before activation; none are claimed passed here.**

## One pending historical payout

1. In an MFA-secured admin review, independently identify milestone/contract, employer/freelancer and both parties' eligibility.
2. Obtain proof of *actual* incoming escrow/settled funds from the provider or bank. A staged database record is not escrow.
3. Compare the approved amount, currency, payout destination, recipient identity and any refund/dispute status.
4. Require documented authorized outgoing transfer and a unique payout reference before marking paid.
5. If the evidence is absent, leave the payout **pending** and preserve the record and audit history.

## Owner prerequisites (not software tasks)

1. Register the business and identify the correct authorized merchant activity. Obtain commercial registration, tax ID and trade license; use Ethiopia's [online trade system](https://etrade.gov.et/) and the [Ministry of Trade's registration guidance](https://motri.gov.et/en/service_category/commercial-registration/view).
2. Ask an Ethiopian financial-regulation lawyer to classify MELA's **actual** offering: learner earnings display, paid educational subscriptions, commissions, escrow, and any proposed stored-value or money-transfer service. **A merchant collecting subscriptions is not automatically a licensed electronic-money issuer.** Do not advertise stored-value wallet transfers until classified.
3. Obtain a written agreement with an [NBE-listed licensed provider](https://nbe.gov.et/payment-instrument-issuers-system-operators/) covering merchant collections, settlements, payer verification, refunds, reconciliation, disputes, chargebacks, limits, and API event security. Verify authorization applies to the proposed transaction model.
4. Produce safeguarding, guardian consent, privacy/data-retention, AML/KYC and customer-support/refund policies suitable for minors; confirm which requirements the provider, merchant and MELA each own.
5. In a private admin evidence repository, record dates and reviewer approval for registration, provider contract, bank ownership, provider sandbox, refund procedures, payout/KYC, escrow requirements and security tests. Keep bank records, identity documents and transfer references out of public GitHub issues.
6. Complete signed-in Android phone test and a separately approved small live provider test only **after** all upstream gates are satisfied.

## Launch rule

**Do not enable `payouts` or `earn_work` or authorize a real payment/withdrawal on the basis of this audit.** There must be signed owner/legal/provider clearance, migration reviewed and applied with rollback, negative-case tests, ledger reconciliation, and production smoke verification. Issue #168 must remain open until evidenced.

## Official references

- National Bank of Ethiopia payment-service licensee list: https://nbe.gov.et/payment-instrument-issuers-system-operators/
- NBE payment-system directives: https://nbe.gov.et/directives/poyment-system/
- Ethiopian Ministry of Trade commercial registration: https://motri.gov.et/en/service_category/commercial-registration/view
- Ethiopian Ministry of Trade licensing: https://www.motri.gov.et/en/service_category/trade-license/view
- Supabase RLS guidance: https://supabase.com/docs/guides/database/postgres/row-level-security

*No usernames, PII, account numbers, secret keys, transfer references or proof documents should be committed here.*

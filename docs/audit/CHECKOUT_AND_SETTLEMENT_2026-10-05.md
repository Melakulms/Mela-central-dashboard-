# Checkout and settlement checkpoint — 5 October 2026

Decision: paid launch remains NO-GO. Newer GitHub mentorship/safeguarding work is preserved; this checkpoint does not certify phases 4–7.

## Implemented

Four migrations record all database changes: pending-only referral attribution, unique unfinished checkouts, removal of the conflicting subscription status check, and trusted-server settlement updates. The original premium_* status vocabulary is used by the finalizer, access checks, expiry job and unique current-subscription index. Its constraint remains intact. No real account was activated and no funds were transferred.

The old public payment trigger reset settlement fields and status even for trusted backend calls. Its replacement still derives insert prices from the server catalog, forbids identity changes and terminal-state rewrites, rejects client-identity updates, and allows the trusted backend to persist verification. Finalization now passes the verified paid amount in minor units instead of a provider fee. Replaying settlement returns the original entitlement without a second activation.

The three checkout paths reuse eligible open sessions. Database uniqueness prevents concurrent initializations for the same course/user/mode, learning-product/user/mode or escrow/mode. Uncertain initialization remains unresolved; an operator/provider verification must establish its state before a new attempt. There is no automatic expiry or reconciliation worker yet. This deliberate behavior can require manual reconciliation after a provider outage.

Referral processing preserves attribution and creates pending 10/20 ETB provisional commissions without earnings-ledger credits. It does not yet implement payment-linked reward settlement. Existing paid history is not rewritten. At initial inspection there were no paid or pending commission rows.

## Evidence

- 208 local automated tests, twelve suites, and production frontend build pass.
- Live rollback-only SQL: referral_payment_gate, open_checkout_uniqueness and learning_payment_contract pass.
- Live tests demonstrate client settlement denial, fee rejection, full-amount Premium activation, idempotent settlement replay, pending 20 ETB Premium referral handling and no spendable referral credit.
- Duplicate course/learning inserts are rejected; a confirmed failed course attempt can be replaced. The escrow unique index is valid. A multi-connection/provider concurrency test remains open.
- Existing newer checkout behavior (Auth timeout, identity validation, mode/key agreement and conditional update result checks) is preserved while adding unique-claim handling, URL validation and uncertainty handling.

## Pricing and remaining dependencies

20 ETB exists as normal_monthly, not an implemented one-time registration charge. Premium is configured as 50 ETB monthly. Commission settings are 10/20 ETB. Learning products are off sale and paid product prices are unset. Do not infer a working registration checkout from these amounts.

Remaining engineering: registration product/payment mapping, verified referral settlement, reconciliation/refunds/disputes, fraud review, translated receipts, provider sandbox acceptance and cross-process load testing. OWNER_ACTION_REQUIRED: provider-issued sandbox access and webhook secret via secure configuration, production billing acceptance, qualified reviewer and local legal sign-off. No live payment flags were enabled.

## Advisor findings still open

- [Privileged function authorization review](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable): 90 authenticated warnings.
- [RLS without policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy): eleven informational findings; private/server-only tables require deliberate disposition.
- [Leaked-password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) remains disabled.

Previous source archives contain known defects and are not suitable for routine rollback. Roll forward with a reviewed migration; never restore automatic unpaid referral credit or the conflicting subscription check.

## Final deployment checkpoint

Deployed versions: chapa-initialize v7, mela-learning-checkout v5, mela-finance v7, mela-learning-payment-verify v4 and mela-learning-payment-callback v8. Newer GitHub checkout code was reconciled before the final deployment, preserving its Auth timeout, mode handling and conditional write response checks. Final readback confirms payments/payouts off, zero learning products on sale, and only the original five free subscription rows. Transactional test subscriptions did not persist.

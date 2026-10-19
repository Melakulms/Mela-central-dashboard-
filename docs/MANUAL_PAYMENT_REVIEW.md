# Real incoming-transfer review integration

The Payments section now contains the actual Supabase-backed review form when `VITE_MANUAL_PAYMENTS_ENABLED=true`. This is proposed source code, not a deployed or enabled live payment service.

Depends on both payment migrations from mela-app PR #56. The first migration is on staging with collection disabled. Automatic approval review declined the cross-bank follow-up migration without stating a reason; it is not installed.

The existing `finance.manage` UI permission controls visibility. The RPC additionally requires explicit payment-reviewer provisioning and an MFA `aal2` session. No bank passwords or OTPs are collected. Use the existing admin Supabase client so the admin session stays segregated from the learner app.

The reviewer must verify an actual successful incoming credit and payment ownership. Enter the customer's reference and the receiving-account reference separately; they can differ across banks. The backend performs atomic matching and entitlement recording and rejects duplicate incoming credits. These are real RPC calls, not browser-simulated approvals.

Do not enable the flag before configuring the permitted receiving account, actual products/prices, payment reviewer, paid-product access enforcement and real end-to-end tests. There is no universal bank-verification API connected. Any sending bank can be entered for manual verification; this does not establish automatic integration with every bank.

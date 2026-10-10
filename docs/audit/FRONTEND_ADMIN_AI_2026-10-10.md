# Frontend, admin and AI release — 10 October 2026

This engineering release closes verified interface and API gaps. It does not certify unrestricted launch or successful production model calls.

## Learner frontend
- Career Coach preserves the last 40 messages and draft in account-scoped tab storage for 30 minutes, with a clear-conversation control and sign-out cleanup. Blocked storage does not stop the chat. No credentials are saved by this feature.
- Follow-ups include bounded recent conversational context; server rejects system-role history, oversized input and unknown languages. Coach controls are translated into English, Amharic, Afaan Oromo, Tigrinya and Somali, and the selected language is passed to the agent.
- Network failures preserve the question. Duplicate submissions are blocked; model text is rendered as escaped text with readable line breaks.

## Admin frontend
- AI Workforce is now reachable through permission-filtered navigation. It receives the existing MFA-verified admin client rather than constructing a second persistent client.
- Agent descriptions, limits and enabled status; retryable loading; serialized agent changes; complete paginated run and approval history with exact totals and status filters; run inspection; approval payload/requester inspection and recorded review reasons.
- Approval queues a task; it does not execute it or grant the reviewer ownership. Existing self-approval and stale-review refusals remain.
- Users now render the actual profile/auth response envelope. Complete account pagination/search/filtering and refreshable details replace the previously truncated list.
- users.manage roles can confirm an account-status change with a written reason through the existing atomic audited RPC, including a stale-record guard. Reader roles remain read-only. This is platform account status, not authentication-provider confirmation or data erasure.
- Audit history now supports pagination, exact totals, action search, before/after/context inspection, retry and safe text rendering.

## AI and API safeguards
- Active account checks before AI use and AI admin inventory; bounded conversation payloads and response-language whitelist; bounded upstream waits.
- Personal, progress, opportunity and course tool reads now use the caller token and RLS, rather than service credentials. Service access remains for execution accounting/audit records.
- Tool assignment, role and approval checks occur before a run is created. An unapproved tool is refused without an orphaned running record or a false claim that approval was queued.
- JWT checks remain enabled. Deployed versions: mela-ai-admin 5, mela-ai-execution-v2 15, mela-admin-api 23.

## Verification
- Learner: 124 tests in 27 suites; production build passes.
- Admin/API: 293 tests in 23 suites; production build passes. Total: 417.
- UI tests cover page navigation/filter resets, real user response shape, failed status/review retries, duplicate-submit prevention, safe audit rendering, history recovery/account separation/expiry/cleanup, language selection and loading failures.
- Handler tests cover MFA and permission refusal, suspended-account refusal, caller-token tool reads, invalid history/language refusal, unowned-session refusal before model calls, bounded pagination, recorded reasons and approval checks before writes.
- Live atomic admin-update rollback regression passes: save+audit together, stale-update rejection, unsupported-column rejection, non-admin rejection and denied browser RPC execution. No customer account was modified in this release.

## Remaining acceptance gates
There are 26 configured/enabled agent records, but the live AI run inventory is empty. No successful production model call is claimed. Signed-in browser/MFA acceptance, provider configuration and response acceptance, native-language review, content/rights/educator review, backup restoration and capacity evidence remain open. The separate readiness review lists 51 empty courses and 23 empty curriculum programs. Payments and other deferred modules remain disabled; invite-only beta remains the release scope.

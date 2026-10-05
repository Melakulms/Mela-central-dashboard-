# Content and AI delivery checkpoint — 5 October 2026

Payments are deferred by the owner. Existing implementation and migration history are preserved. Payment readiness remains 13%; no financial feature was enabled or payment endpoint modified in this checkpoint. This is not approval for a paid launch.

## Phase 8 — delivered and verified

The latest upstream Content Studio already has draft/version storage, admin controls and 23 empty-program draft shells. Those shells are not complete lessons. This release adds two original, complete introductory lesson drafts:

- TVET Applied Mathematics: Unit prices and a materials budget.
- TVET Applied English & Communication: A clear workplace request and confirmation.

Each structured JSON file contains objectives, lesson explanation, contextual examples, three practice questions with answers/explanations, an independent task, assessment criteria, accessibility notes and translation status. Fictional Birr prices are clearly identified. The SQL migration inserts separate chapter drafts without overwriting existing shells or drafts. Live reads confirmed both records are draft version 1, with no reviewer identity. Nothing was published or marked approved.

Remaining engineering/content work: complete the other program lessons and book inventory, implement qualified review-to-publication delivery, map official curriculum, and complete four translations per English lesson. This is two lessons, not completion of 23 programs or the 53-field program. The canonical ordered 53-field list is still unidentified.

OWNER_ACTION_REQUIRED: canonical 53-field list/order, qualified subject reviewers, native-language reviewers and approved source rights/curriculum mapping. No fabricated review is accepted.

## Phase 9 — delivered and verified

Live inventory contains 26 enabled agent configurations. This does not establish that 26 workflows are functional or free to operate. The existing OpenAI proxy can incur provider charges; no provider balance, free tier or budget agreement was inferred.

Recovered and version-controlled the existing coordinator, execution service and proxy. Fixed:

- Admin request payload now matches the execution endpoint's `message` contract.
- Execution profile query now uses the required equality operator.
- Queued tasks load their own persisted description instead of failing with an empty message.
- Report export through this AI path is denied pending permission-specific implementation; a profile `admin` label is not accepted as export authority.
- Coordinator and execution each make one attempt; failures do not trigger stacked retries.
- Proxy validates the bearer token with Auth before any provider request.
- Service-only, transactional quota reservation limits gateway attempts to 10 per active user and 100 globally per Addis Ababa calendar day. A shared row lock serializes reservations. Failed or ambiguous provider attempts retain their reservation. These are request limits, not exact Birr billing limits.
- Proxy caps output at 800 completion tokens, sets provider storage false and uses network timeouts. Caller-supplied system messages are demoted; a server-owned safety instruction treats every learner as potentially under 18.

Deployed: `mela-openai-proxy` v4, `mela-ai-execution-v2` v13, `mela-ai-coordinator-v2` v9; JWT verification enabled for all three.

Validation: 225 automated tests in 15 suites pass; admin production build passes. Database rollback regression checks per-user/global limits, disabled state, missing identity and denied browser execution grants. A service-role rollback call successfully reserves an attempt. No model request was made during acceptance tests and no test quota rows persisted.

Security advisor: 90 authenticated privileged-function warnings, one intentional public-certificate warning, leaked-password protection warning and 15 no-policy information findings. The new two private tables deliberately grant no browser access. Performance advisor reports unused-index information only. See [privileged function guidance](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) and [password protection guidance](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

## Phase 9 limitations and release gates

This gateway guard does not prove all legacy Gemini/tutor/proxy routes share a single limit. Those routes must be consolidated or independently disabled/guarded before claiming platform-wide cost control. Existing agent enable/disable controls remain; a global gateway switch exists in service-only `private.mela_ai_gateway_limits`, but its MFA admin UI and audited configuration endpoint are still needed.

A system instruction is not a tested child-safety filter. Input/output moderation, age/consent integration, multilingual adversarial evaluation, privacy retention review and a complete provider-backed authenticated user journey remain open. Do not certify Phase 9 from mocked provider responses. Task-claim concurrency and legacy tool/approval permissions also require further acceptance testing.

OWNER_ACTION_REQUIRED: confirm the AI provider funding/free-tier policy and acceptable usage allowance, appoint safeguarding reviewers, and provide acceptance participants through normal sign-in. Never send credentials or MFA codes in chat.

## Rollback and go/no-go

NO-GO for unrestricted public/paid launch. Readiness percentages are unchanged: these targeted repairs do not satisfy broader acceptance gates. Preserve the quota migration on rollback; disable the gateway using its service-only configuration rather than restoring an unbounded proxy. Restore frontend code through a reviewed revert if needed. Archive lesson drafts instead of deleting version history.

update public.platform_launch_requirements
set evidence_note='Re-verified 2026-10-03 after source-freshness maintenance repair: 21 real open verified opportunities are currently available, exceeding the launch threshold of 10. The catalog includes an October launch-window buffer and stale official sources are automatically deactivated.'
where requirement_key='real_opportunity_supply';

update public.platform_launch_requirements
set evidence_note='Re-verified 2026-10-03 against current official sources: 10 real open verified scholarship opportunities are currently available, exceeding the launch threshold of 5. Chevening and Knight-Hennessy were freshly reverified, and the ALU January 2027 deadline was corrected to 30 November 2026 from the official admissions source.'
where requirement_key='real_scholarship_supply';

update public.platform_launch_requirements
set evidence_note='Re-verified 2026-10-03: learner deployment commit dd447809415b9f299951a1a78a987ac6303494da passed CI, production build, GitHub Pages deploy, public-page smoke, Supabase Auth health, launch-critical Auth-settings smoke (email signup enabled and email autoconfirm disabled), and Data API smoke. Central-admin CI is also green. Gate remains pending only because authenticated real-user browser E2E on the final hosted environment has not yet been completed and recorded.'
where requirement_key='staging_verified';

update public.platform_launch_requirements
set evidence_note='Re-verified 2026-10-03: operational health has 257/257 public tables with RLS, 0 unreviewed anonymous SECURITY DEFINER exposures, 1 explicitly allowlisted public certificate verifier, 0 stale external opportunity sources, and 0 critical alerts. The source-freshness cron defect was repaired and the underlying maintenance function now succeeds; one historical failed run remains visible only inside the rolling 24-hour warning window.'
where requirement_key='observability';

update public.platform_launch_requirements
set evidence_note='Re-verified 2026-10-03: the deployed learner app now fails its production deployment if email signup is disabled or email autoconfirm is enabled; the live post-deploy Auth-settings smoke passed. Forgot-password request and recovery-token completion UI are implemented with a 12-character minimum. Gate remains pending until custom SMTP is configured and a real confirmation plus password-recovery email round trip succeeds on the final hosted domain.'
where requirement_key='email_recovery';

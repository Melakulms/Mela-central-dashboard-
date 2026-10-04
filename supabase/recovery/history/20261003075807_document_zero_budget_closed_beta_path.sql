-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261003075807
update public.platform_launch_requirements
set evidence_note = 'Zero-budget closed-beta path deployed 2026-10-03: new beta accounts use admin-issued one-time access codes, usernames, server-confirmed Supabase Auth users, and rotating recovery codes, so closed-beta onboarding does not depend on email delivery. Production custom SMTP is still required before unrestricted public email signup/recovery is treated as launch-ready.', updated_at = now()
where requirement_key = 'custom_smtp';

update public.platform_launch_requirements
set evidence_note = 'Zero-budget closed-beta recovery deployed 2026-10-03: beta users reset passwords with a high-entropy recovery code whose hash is stored server-side and rotated after successful reset. Existing email-account recovery remains implemented. Public-launch email confirmation/reset round-trip remains pending until production SMTP and final-domain delivery are available.', updated_at = now()
where requirement_key = 'email_recovery';

update public.platform_launch_requirements
set evidence_note = 'Re-verified 2026-10-03: learner production build, CI and GitHub Pages deployment are green. The release pipeline now calls the live invite-only beta-auth status endpoint and fails deployment unless beta access is enabled, invite-only and email-independent. Central admin CI is green and the Beta Invites panel is deployed. Gate remains pending because a full authenticated real-user browser lifecycle across launch roles has not yet been recorded.', updated_at = now()
where requirement_key = 'staging_verified';
;

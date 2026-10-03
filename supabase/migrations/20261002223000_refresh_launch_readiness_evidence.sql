-- Production-applied refresh of launch-readiness evidence after the 2026-10-02 audit.
-- Do not preserve stale August supply counts after opportunities expire.

update public.platform_launch_requirements
set manual_status='pending', completed_at=null,
    evidence_note='Re-audited 2026-10-02 against the production catalog: only 2 currently open, source-verified real opportunities remain. The launch threshold is 10, so this gate is pending until fresh verified supply is restored. Expired/closed records are not counted.'
where requirement_key='real_opportunity_supply';

update public.platform_launch_requirements
set manual_status='pending', completed_at=null,
    evidence_note='Re-audited 2026-10-02 against the production catalog: only 2 currently open, source-verified scholarship records remain. The launch threshold is 5, so this gate is pending until fresh verified scholarship supply is restored.'
where requirement_key='real_scholarship_supply';

update public.platform_launch_requirements
set evidence_note='Re-verified 2026-10-02: all 257 public tables have Row Level Security enabled.'
where requirement_key='rls_all_public';

update public.platform_launch_requirements
set evidence_note='Re-verified 2026-10-02: there are 0 unreviewed anonymous SECURITY DEFINER API exposures. The single anonymous SECURITY DEFINER endpoint is the explicitly allowlisted high-entropy course-certificate verifier, which returns only public credential verification fields.'
where requirement_key='no_public_security_definers';

update public.platform_launch_requirements
set evidence_note='Re-audited 2026-10-02: the current learner and central-admin main branches are deployed to GitHub Pages and their production build/deploy/public-page/Auth/Data-API smoke checks pass. This gate remains pending because authenticated real-user browser E2E on the final hosted environment has not yet been completed and recorded.'
where requirement_key='staging_verified';

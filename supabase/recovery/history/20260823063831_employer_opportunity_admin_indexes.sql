-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260823063831
create index if not exists employer_registration_requests_admin_queue_idx on public.employer_registration_requests(status, created_at desc);
create index if not exists company_profiles_verification_admin_idx on public.company_profiles(verification_status, created_at desc);
create index if not exists opportunities_moderation_admin_idx on public.opportunities(moderation_status, status, created_at desc);
create index if not exists opportunities_employer_admin_idx on public.opportunities(employer_id, created_at desc);

;

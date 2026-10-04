-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821233004
do $$
declare
  r record;
  sensitive_tables text[] := array[
    'applications','candidate_matches','coin_transactions','employer_members','employer_registration_requests','employer_verification_documents','guardian_relationships','notification_preferences','notifications','opportunity_reminders','payout_requests','practice_attempts','practice_mastery','practice_user_stats','profile_documents','profile_education','profile_experience','profile_languages','profile_projects','saved_opportunities'
  ];
begin
  for r in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname='public'
      and tablename = any(sensitive_tables)
      and (
        policyname in ('mela_gate_platform_live','mela_gate_opportunities','mela_gate_career_passport','mela_gate_practice','mela_verified_active_gate_v35')
        or policyname like 'mela_master_gate%'
      )
  loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;
;

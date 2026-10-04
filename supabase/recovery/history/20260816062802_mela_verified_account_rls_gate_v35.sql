-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260816062802
do $$
declare t text;
begin
 foreach t in array array[
  'applications','application_notes','application_status_history','external_application_tracking','external_application_events',
  'guardian_relationships','student_lesson_progress','student_module_progress','lesson_progress','course_enrollments',
  'mela_user_learning_entitlements','mela_learning_payment_attempts','payments','notifications','notification_preferences',
  'earnings_ledger','career_passport_achievements','profile_documents','profile_education','profile_experience','profile_languages','profile_projects',
  'employers','employer_members','opportunities','student_profiles','parent_profiles','teacher_profiles','company_profiles','user_subscriptions','parent_link_invites'
 ] loop
   if to_regclass('public.'||t) is not null then
     execute format('drop policy if exists mela_verified_active_gate_v35 on public.%I',t);
     execute format('create policy mela_verified_active_gate_v35 on public.%I as restrictive for all to authenticated using (private.current_account_can_access()) with check (private.current_account_can_access())',t);
   end if;
 end loop;
end $$;
;

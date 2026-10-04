-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260922150608
create policy "student_profiles_self_insert" on public.student_profiles for insert to authenticated with check (user_id = (select auth.uid()));
;

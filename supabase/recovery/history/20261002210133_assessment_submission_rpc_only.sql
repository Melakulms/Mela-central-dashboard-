-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002210133
drop policy if exists "Students submit own attempt" on public.assessment_attempts;
revoke update on table public.assessment_attempts from authenticated;

grant select, insert on table public.assessment_attempts to authenticated;
grant execute on function public.submit_my_assessment_attempt(uuid) to authenticated;

;

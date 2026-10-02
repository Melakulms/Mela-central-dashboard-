-- Production-applied final assessment boundary: browsers may start/read attempts,
-- but submission/status mutation is only through the audited owner-only RPC.

drop policy if exists "Students submit own attempt" on public.assessment_attempts;
revoke update on table public.assessment_attempts from authenticated;

grant select, insert on table public.assessment_attempts to authenticated;
grant execute on function public.submit_my_assessment_attempt(uuid) to authenticated;

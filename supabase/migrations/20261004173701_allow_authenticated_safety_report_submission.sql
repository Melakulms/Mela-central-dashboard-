-- Phase 7: RLS/trigger own the learner submission boundary; authenticated users need INSERT privilege to reach it.
grant insert on table public.reports to authenticated;
revoke update, delete on table public.reports from authenticated;

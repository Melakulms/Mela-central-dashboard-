-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812215251
revoke all privileges on public.mentorship_requests from authenticated;
grant select on public.mentorship_requests to authenticated;
grant insert (mentor_id,mentee_id,topic,message,preferred_at,status) on public.mentorship_requests to authenticated;
grant update (status,preferred_at) on public.mentorship_requests to authenticated;
grant all on public.mentorship_requests to service_role;

revoke all privileges on public.mentorship_sessions from authenticated;
grant select on public.mentorship_sessions to authenticated;
grant update (scheduled_at,duration_min,status,notes) on public.mentorship_sessions to authenticated;
grant all on public.mentorship_sessions to service_role;

;

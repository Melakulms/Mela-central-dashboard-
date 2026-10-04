-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822082841
revoke execute on function private.cleanup_video_call_transients() from authenticated, anon; revoke execute on function private.gated_refresh_arena_daily_metrics(date) from authenticated, anon; revoke execute on function private.refresh_career_path_enrollment(uuid,uuid) from authenticated, anon; revoke execute on function private.refresh_work_reputation(uuid,uuid) from authenticated, anon; revoke execute on function private.record_arena_integrity_event_for_user(uuid,uuid,text,uuid,jsonb) from authenticated, anon; revoke execute on function private.refresh_candidate_matches(uuid) from authenticated, anon;
;

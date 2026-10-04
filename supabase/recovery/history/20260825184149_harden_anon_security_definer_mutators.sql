-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825184149
REVOKE EXECUTE ON FUNCTION private.advance_sponsored_challenge_lifecycle() FROM anon;
REVOKE EXECUTE ON FUNCTION private.cleanup_video_call_transients() FROM anon;
REVOKE EXECUTE ON FUNCTION private.gated_advance_arena_rounds() FROM anon;
REVOKE EXECUTE ON FUNCTION private.gated_advance_arena_season_lifecycle() FROM anon;
REVOKE EXECUTE ON FUNCTION private.gated_advance_sponsored_challenge_lifecycle() FROM anon;
REVOKE EXECUTE ON FUNCTION private.gated_process_arena_matchmaking() FROM anon;
REVOKE EXECUTE ON FUNCTION private.gated_process_due_opportunity_reminders() FROM anon;
REVOKE EXECUTE ON FUNCTION private.gated_refresh_arena_daily_metrics(date) FROM anon;
REVOKE EXECUTE ON FUNCTION private.refresh_career_path_enrollment(uuid,uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION private.refresh_work_reputation(uuid,uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION private.process_due_opportunity_reminders() FROM anon;
;

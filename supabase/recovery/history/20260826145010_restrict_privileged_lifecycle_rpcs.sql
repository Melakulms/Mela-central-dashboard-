-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826145010
REVOKE EXECUTE ON FUNCTION public.publish_sponsored_challenge(uuid) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_arena_season_status(uuid,text) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.remove_arena_judge(uuid,uuid) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.complete_video_call_recording(uuid,text) FROM anon, authenticated;
;

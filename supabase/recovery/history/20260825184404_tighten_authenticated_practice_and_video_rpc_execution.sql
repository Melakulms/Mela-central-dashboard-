-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825184404
REVOKE EXECUTE ON FUNCTION private.can_access_video_room(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION private.complete_practice_session(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION private.start_practice_mock(uuid,integer,smallint) FROM anon;
REVOKE EXECUTE ON FUNCTION private.start_practice_session(uuid,text,integer,smallint) FROM anon;
REVOKE EXECUTE ON FUNCTION private.submit_practice_response(uuid,uuid,jsonb,integer,text) FROM anon;
REVOKE EXECUTE ON FUNCTION private.get_my_practice_dashboard() FROM anon;
REVOKE EXECUTE ON FUNCTION private.get_my_practice_recommendations(integer) FROM anon;
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825184419
REVOKE EXECUTE ON FUNCTION private.can_access_video_room(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.complete_practice_session(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.start_practice_mock(uuid,integer,smallint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.start_practice_session(uuid,text,integer,smallint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.submit_practice_response(uuid,uuid,jsonb,integer,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.get_my_practice_dashboard() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.get_my_practice_recommendations(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.can_access_video_room(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.complete_practice_session(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.start_practice_mock(uuid,integer,smallint) TO authenticated;
GRANT EXECUTE ON FUNCTION private.start_practice_session(uuid,text,integer,smallint) TO authenticated;
GRANT EXECUTE ON FUNCTION private.submit_practice_response(uuid,uuid,jsonb,integer,text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.get_my_practice_dashboard() TO authenticated;
GRANT EXECUTE ON FUNCTION private.get_my_practice_recommendations(integer) TO authenticated;
;

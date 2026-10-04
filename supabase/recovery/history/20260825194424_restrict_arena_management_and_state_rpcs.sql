-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825194424
REVOKE EXECUTE ON FUNCTION private.get_arena_leaderboard(text,text,text,uuid,uuid,integer) FROM anon;
REVOKE EXECUTE ON FUNCTION private.get_arena_live_scoreboard(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION private.get_arena_live_state(uuid) FROM anon;
;

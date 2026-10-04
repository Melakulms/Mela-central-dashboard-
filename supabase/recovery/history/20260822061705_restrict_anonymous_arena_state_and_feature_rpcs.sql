-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822061705
revoke execute on function public.get_arena_live_scoreboard(uuid) from anon, public; revoke execute on function public.get_arena_live_state(uuid) from anon, public; revoke execute on function public.platform_feature_available(text) from anon, public; revoke execute on function public.platform_feature_enabled(text) from anon, public;
;

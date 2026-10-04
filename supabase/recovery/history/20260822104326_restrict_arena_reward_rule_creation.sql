-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822104326
revoke execute on function public.add_arena_reward_rule(uuid,uuid,integer,text,integer,numeric,text,uuid,text) from authenticated; revoke execute on function private.add_arena_reward_rule(uuid,uuid,integer,text,integer,numeric,text,uuid,text) from authenticated;
;

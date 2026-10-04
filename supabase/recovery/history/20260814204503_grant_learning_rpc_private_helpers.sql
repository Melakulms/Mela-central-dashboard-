-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814204503
grant execute on function private.activate_my_educator_profile(uuid,text,text[],text[]) to authenticated,service_role; grant execute on function private.create_my_classroom(text,text,text) to authenticated,service_role; grant execute on function private.join_educator_classroom(text) to authenticated,service_role; grant execute on function private.record_educator_observation(uuid,uuid,uuid,numeric,text,text) to authenticated,service_role; grant execute on function private.set_my_mela_next_goal(text,text,uuid,date) to authenticated,service_role;
;

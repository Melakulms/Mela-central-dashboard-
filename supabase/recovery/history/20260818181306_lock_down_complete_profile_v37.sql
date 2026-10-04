-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260818181306
revoke all on function public.complete_my_profile_v37(text,text,text,text,text,jsonb) from anon;
revoke all on function public.complete_my_profile_v37(text,text,text,text,text,jsonb) from public;
grant execute on function public.complete_my_profile_v37(text,text,text,text,text,jsonb) to authenticated;
grant execute on function public.complete_my_profile_v37(text,text,text,text,text,jsonb) to service_role;
;

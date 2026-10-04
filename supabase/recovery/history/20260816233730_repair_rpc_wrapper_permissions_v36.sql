-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260816233730
grant execute on function private.select_account_type_v35(public.user_role) to authenticated,service_role;
grant execute on function private.create_parent_link_invite_v35() to authenticated,service_role;
grant execute on function private.redeem_parent_link_invite_v35(text) to authenticated,service_role;
grant execute on function private.set_my_education_stage_v36(text,integer,text) to authenticated,service_role;
grant execute on function private.track_global_source_v16(uuid) to authenticated,service_role;
grant execute on function private.get_arena_leaderboard(text,text,text,uuid,uuid,integer) to anon,authenticated,service_role;
grant execute on function private.get_question_quality_progress_v21() to authenticated,service_role;
grant execute on function private.review_opportunity_v35(uuid,text,text) to authenticated,service_role;

create or replace function private.get_my_dashboard_v36()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_role public.user_role;
  v_role_selected timestamptz;
begin
  if v_uid is null then raise exception 'authentication required' using errcode='42501'; end if;
  if not private.current_account_can_access() then raise exception 'verified active account required' using errcode='42501'; end if;
  select p.role,p.role_selected_at into v_role,v_role_selected from public.profiles p where p.id=v_uid;
  if v_role in ('student'::public.user_role,'parent'::public.user_role,'teacher'::public.user_role,'company'::public.user_role) and v_role_selected is null then
    raise exception 'account type selection required' using errcode='42501';
  end if;
  return public.get_my_dashboard();
end;
$$;
revoke all on function private.get_my_dashboard_v36() from public,anon;
grant execute on function private.get_my_dashboard_v36() to authenticated,service_role;

create or replace function public.get_my_dashboard_v36()
returns jsonb
language sql
set search_path=''
as $$ select private.get_my_dashboard_v36(); $$;
revoke all on function public.get_my_dashboard_v36() from public,anon;
grant execute on function public.get_my_dashboard_v36() to authenticated,service_role;
;

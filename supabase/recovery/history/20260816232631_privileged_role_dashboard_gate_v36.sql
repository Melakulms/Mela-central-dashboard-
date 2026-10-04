-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260816232631
create or replace function public.get_my_dashboard_v36()
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
  if v_uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  if not private.current_account_can_access() then
    raise exception 'verified active account required' using errcode='42501';
  end if;
  select p.role,p.role_selected_at into v_role,v_role_selected from public.profiles p where p.id=v_uid;
  if v_role in ('student'::public.user_role,'parent'::public.user_role,'teacher'::public.user_role,'company'::public.user_role) and v_role_selected is null then
    raise exception 'account type selection required' using errcode='42501';
  end if;
  return public.get_my_dashboard();
end;
$$;
revoke all on function public.get_my_dashboard_v36() from public, anon;
grant execute on function public.get_my_dashboard_v36() to authenticated, service_role;
;

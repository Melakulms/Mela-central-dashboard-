-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260816232543
revoke execute on function public.get_my_dashboard() from public, anon, authenticated;
grant execute on function public.get_my_dashboard() to service_role;

create or replace function public.get_my_dashboard_v36()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  if not private.current_account_can_access() then
    raise exception 'verified active account required' using errcode='42501';
  end if;
  if not exists(select 1 from public.profiles p where p.id=v_uid and p.role_selected_at is not null) then
    raise exception 'account type selection required' using errcode='42501';
  end if;
  return public.get_my_dashboard();
end;
$$;
revoke all on function public.get_my_dashboard_v36() from public, anon;
grant execute on function public.get_my_dashboard_v36() to authenticated, service_role;
;

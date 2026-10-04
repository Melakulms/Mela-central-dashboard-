-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260819053132

begin;

alter function public.complete_my_profile_v37(text,text,text,text,text,jsonb)
  set schema private;

alter function private.complete_my_profile_v37(text,text,text,text,text,jsonb)
  rename to complete_my_profile_v37_impl;

revoke all on function private.complete_my_profile_v37_impl(text,text,text,text,text,jsonb)
  from public, anon, authenticated;
grant execute on function private.complete_my_profile_v37_impl(text,text,text,text,text,jsonb)
  to authenticated, service_role;

create function public.complete_my_profile_v37(
  p_full_name text,
  p_preferred_language text default 'en',
  p_city text default null,
  p_region text default null,
  p_institution_name text default null,
  p_details jsonb default '{}'::jsonb
)
returns public.profiles
language sql
security invoker
set search_path = ''
as $wrapper$
  select private.complete_my_profile_v37_impl(
    p_full_name,
    p_preferred_language,
    p_city,
    p_region,
    p_institution_name,
    p_details
  );
$wrapper$;

revoke all on function public.complete_my_profile_v37(text,text,text,text,text,jsonb)
  from public, anon;
grant execute on function public.complete_my_profile_v37(text,text,text,text,text,jsonb)
  to authenticated, service_role;

comment on function public.complete_my_profile_v37(text,text,text,text,text,jsonb)
  is 'Authenticated, security-invoker API wrapper for the private profile-completion implementation.';

commit;

;

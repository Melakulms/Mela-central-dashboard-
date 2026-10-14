-- Non-mutating production regression assertions: browser roles must not be able
-- to rewrite school placement, verified contact details or onboarding flags.
do $test$
declare c text;
begin
  foreach c in array array['email','phone_number','education_stage_key','grade_level','onboarding_step'] loop
    if has_column_privilege('authenticated','public.profiles',c,'UPDATE') or
       has_column_privilege('anon','public.profiles',c,'UPDATE') then
      raise exception 'Unsafe direct profiles column UPDATE grant remains: %',c;
    end if;
  end loop;
  if not has_column_privilege('authenticated','public.profiles','preferred_language','UPDATE') then
    raise exception 'User-editable preferred language unexpectedly blocked';
  end if;
  if not exists(
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname='set_my_education_stage_v36'
      and p.prosecdef and pg_get_userbyid(p.proowner)='postgres'
  ) then raise exception 'Trusted education-stage RPC missing security definer authority'; end if;
end $test$;

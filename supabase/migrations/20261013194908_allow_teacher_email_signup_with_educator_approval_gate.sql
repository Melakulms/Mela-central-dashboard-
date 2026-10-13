-- Executed on MELA production as migration 20261013194908.
-- Give email-verified teachers an application role, not immediate educator authority.
do $migration$
declare
  definition text;
  marker text := 'if v_requested_role in (''student'',''parent'',''company'') then';
begin
  select pg_get_functiondef('private.handle_new_auth_user()'::regprocedure) into definition;
  if position(marker in definition)=0 then
    raise exception 'Unexpected registration trigger: review before changing allowed account roles';
  end if;
  execute replace(definition, marker,
    'if v_requested_role in (''student'',''parent'',''teacher'',''company'') then');
end $migration$;

-- A role claim does not grant classroom management. Keep it gated until
-- independent teacher verification by the Central Dashboard review process.
do $migration$
declare
  definition text;
  marker text := 'if r <> ''teacher'' then raise exception ''only teacher accounts may manage educator classrooms''; end if;';
  replacement text := marker || chr(10) ||
    'if not exists (' || chr(10) ||
    '  select 1 from public.teacher_profiles t' || chr(10) ||
    '  join public.profiles p on p.id=t.user_id' || chr(10) ||
    '  where t.user_id=(select auth.uid())' || chr(10) ||
    '    and t.verification_status in (''approved'',''verified'')' || chr(10) ||
    '    and p.account_status=''active'' and p.email_verified' || chr(10) ||
    ') then raise exception ''approved teacher verification required to manage classrooms''; end if;';
begin
  select pg_get_functiondef('private.guard_educator_classroom_role()'::regprocedure) into definition;
  if position(marker in definition)=0 then
    raise exception 'Unexpected classroom role guard: review before changing it';
  end if;
  execute replace(definition, marker, replacement);
end $migration$;

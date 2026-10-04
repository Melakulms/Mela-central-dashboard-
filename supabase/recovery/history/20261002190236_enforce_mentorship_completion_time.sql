-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002190236
create or replace function private.complete_mentorship_session(
  p_session_id uuid,
  p_notes text default null::text
)
returns public.mentorship_sessions
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_row public.mentorship_sessions%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select * into v_row
  from public.mentorship_sessions
  where id = p_session_id
  for update;

  if not found then raise exception 'session not found'; end if;
  if v_row.mentor_id <> v_uid and not private.is_admin_user() then
    raise exception 'only mentor or admin can complete a session';
  end if;
  if v_row.status <> 'scheduled' then
    raise exception 'session is not scheduled';
  end if;
  if v_row.scheduled_at > now() then
    raise exception 'session cannot be completed before its scheduled time';
  end if;

  update public.mentorship_sessions
  set status = 'completed',
      completed_at = now(),
      updated_at = now(),
      notes = coalesce(nullif(trim(coalesce(p_notes, '')), ''), notes)
  where id = p_session_id
  returning * into v_row;

  return v_row;
end;
$function$;
;

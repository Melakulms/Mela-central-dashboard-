-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813101138
create or replace function public.respond_mentorship_request(p_request_id uuid, p_decision text)
returns public.mentorship_requests
language plpgsql
security invoker
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_row public.mentorship_requests%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_decision not in ('accepted','declined') then raise exception 'decision must be accepted or declined'; end if;

  update public.mentorship_requests
     set status=p_decision, responded_at=now()
   where id=p_request_id
     and status='pending'
     and (mentor_id=v_uid or private.is_admin_user())
  returning * into v_row;

  if not found then raise exception 'pending mentorship request not found or not authorized'; end if;
  return v_row;
end;
$$;

grant execute on function public.respond_mentorship_request(uuid,text) to authenticated;
revoke execute on function private.respond_mentorship_request(uuid,text) from authenticated, anon, public;
;

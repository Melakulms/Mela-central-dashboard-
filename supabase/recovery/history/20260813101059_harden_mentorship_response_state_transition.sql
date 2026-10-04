-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813101059
create or replace function private.respond_mentorship_request(p_request_id uuid, p_decision text)
returns public.mentorship_requests
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_row public.mentorship_requests%rowtype;
  v_exists public.mentorship_requests%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_decision not in ('accepted','declined') then raise exception 'decision must be accepted or declined'; end if;

  update public.mentorship_requests
     set status=p_decision, responded_at=now()
   where id=p_request_id
     and status='pending'
     and (mentor_id=v_uid or private.is_admin_user())
  returning * into v_row;

  if found then
    insert into public.notifications(user_id,title,body,ref_table,ref_id)
    values(v_row.mentee_id,'Mentorship request update','Your mentorship request was '||p_decision||'.','mentorship_requests',v_row.id);
    return v_row;
  end if;

  select * into v_exists from public.mentorship_requests where id=p_request_id;
  if not found then raise exception 'request not found'; end if;
  if v_exists.mentor_id<>v_uid and not private.is_admin_user() then raise exception 'only the mentor or admin can respond'; end if;
  raise exception 'request is no longer pending';
end;
$$;
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825153743
begin;

create or replace function public.admin_review_employer_registration(p_request_id uuid, p_status text, p_review_notes text)
returns public.employer_registration_requests
language plpgsql
security definer
set search_path = public
as $$
declare r public.employer_registration_requests;
begin
  if p_status not in ('approved','rejected','pending','review') then raise exception 'invalid employer status'; end if;
  if p_status in ('approved','rejected') and nullif(trim(p_review_notes),'') is null then raise exception 'review reason is required'; end if;
  update public.employer_registration_requests
     set status=p_status, review_notes=nullif(trim(p_review_notes),''), reviewed_at=now()
   where id=p_request_id
     and status in ('pending','review','review_required')
     and ((status='pending' and p_status in ('pending','review','approved','rejected')) or
          (status='review' and p_status in ('pending','review','approved','rejected')) or
          (status='review_required' and p_status in ('review','approved','rejected')))
  returning * into r;
  if not found then raise exception 'invalid transition or concurrent modification'; end if;
  return r;
end;
$$;

create or replace function public.admin_review_opportunity(p_opportunity_id uuid, p_status text, p_moderation_notes text)
returns public.opportunities
language plpgsql
security definer
set search_path = public
as $$
declare r public.opportunities;
begin
  if p_status not in ('approved','rejected','pending','flagged') then raise exception 'invalid moderation status'; end if;
  if p_status in ('approved','rejected') and nullif(trim(p_moderation_notes),'') is null then raise exception 'review reason is required'; end if;
  update public.opportunities
     set moderation_status=p_status,
         moderation_notes=nullif(trim(p_moderation_notes),''),
         verified_active=(p_status='approved'),
         updated_at=now()
   where id=p_opportunity_id
     and moderation_status in ('pending','flagged','rejected','approved')
     and ((moderation_status='pending' and p_status in ('approved','rejected','flagged')) or
          (moderation_status='flagged' and p_status in ('pending','approved','rejected')) or
          (moderation_status='rejected' and p_status='pending') or
          (moderation_status='approved' and p_status='flagged'))
  returning * into r;
  if not found then raise exception 'invalid transition or concurrent modification'; end if;
  return r;
end;
$$;

revoke all on function public.admin_review_employer_registration(uuid,text,text) from public, anon, authenticated;
revoke all on function public.admin_review_opportunity(uuid,text,text) from public, anon, authenticated;
commit;
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812214131
-- Secure proctoring: students may record raw client events, but cannot self-clear proctoring.

create table if not exists public.proctor_reviews (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.assessment_attempts(id) on delete cascade,
  reviewer_id uuid references public.profiles(id) on delete set null,
  decision text not null check (decision in ('clear','flagged')),
  face_detection_confidence numeric check (face_detection_confidence is null or (face_detection_confidence>=0 and face_detection_confidence<=1)),
  tab_switch_count integer not null default 0 check (tab_switch_count>=0),
  notes text,
  created_at timestamptz not null default now()
);
alter table public.proctor_reviews enable row level security;
create index if not exists proctor_reviews_attempt_created_idx on public.proctor_reviews(attempt_id,created_at desc);

create policy "Proctor reviews visible to student or admin" on public.proctor_reviews for select to authenticated
using (
  exists(select 1 from public.assessment_attempts a where a.id=attempt_id and a.user_id=(select auth.uid()))
  or private.is_admin_user()
);
grant select on public.proctor_reviews to authenticated;
revoke insert,update,delete on public.proctor_reviews from authenticated,anon;

-- Replace permissive proctor event insertion with raw-event-only policy.
drop policy if exists "Students submit own proctor events" on public.proctor_audit_logs;
create policy "Students submit raw proctor events" on public.proctor_audit_logs for insert to authenticated
with check (
  user_id=(select auth.uid())
  and event_type in ('camera_permission','face_presence_client','tab_hidden','tab_visible','fullscreen_exit','fullscreen_enter','window_blur','window_focus','network_change')
  and face_detection_confidence is null
  and coalesce(tab_switch_count,0)=0
  and coalesce(flagged,false)=false
  and flagged_reason is null
  and exists(
    select 1 from public.assessment_attempts a
    where a.id=attempt_id and a.user_id=(select auth.uid()) and a.proctored=true and a.status='in_progress'
  )
);
revoke insert on public.proctor_audit_logs from authenticated;
grant insert (user_id,assessment_title,attempt_id,event_type,details) on public.proctor_audit_logs to authenticated;

-- Server/admin review is authoritative. It calculates tab switches from raw events.
create or replace function private.apply_proctor_review()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare
  v_user uuid;
  v_proctored boolean;
  v_score numeric;
  v_tabs integer;
  v_integrity numeric;
begin
  select a.user_id,a.proctored,a.score into v_user,v_proctored,v_score
  from public.assessment_attempts a where a.id=new.attempt_id for update;
  if not found or not v_proctored then raise exception 'attempt is not a proctored assessment'; end if;

  select count(*)::int into v_tabs
  from public.proctor_audit_logs l
  where l.attempt_id=new.attempt_id and l.event_type='tab_hidden';
  new.tab_switch_count:=v_tabs;

  v_integrity:=greatest(0,least(100,coalesce(new.face_detection_confidence,1)*100-least(v_tabs*5,30)));
  update public.assessment_attempts
  set integrity_score=v_integrity,
      proctor_status=new.decision,
      status=case when new.decision='clear' and score is not null then 'graded' else 'review_required' end,
      reviewed_at=now()
  where id=new.attempt_id;

  if new.decision='clear' and v_score is not null then
    perform private.issue_assessment_verified_skill(new.attempt_id);
    perform private.create_notification(v_user,'Proctored assessment verified','Your proctored assessment review passed and verified skill evidence is now eligible for your Career Passport.','assessment_attempts',new.attempt_id);
  else
    perform private.create_notification(v_user,'Proctored assessment needs review','Your proctored assessment was flagged. Mela review notes are available in your assessment history.','assessment_attempts',new.attempt_id);
  end if;
  return new;
end;$$;
revoke all on function private.apply_proctor_review() from public,anon,authenticated;
drop trigger if exists trg_apply_proctor_review on public.proctor_reviews;
create trigger trg_apply_proctor_review before insert on public.proctor_reviews
for each row execute function private.apply_proctor_review();

-- Legacy session_summary rows are now accepted only when explicitly marked as a server review.
create or replace function private.process_proctor_session_summary()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
begin
  if new.attempt_id is null or new.event_type<>'session_summary' then return new; end if;
  if coalesce(new.details->>'source','')<>'server_review' then
    raise exception 'session_summary is server managed';
  end if;
  return new;
end;$$;
revoke all on function private.process_proctor_session_summary() from public,anon,authenticated;

;

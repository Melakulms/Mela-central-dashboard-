-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812213420
-- Mela backend foundations: storage, auth defaults, matching RPC, proctor ingestion, least privilege.

-- 1) Storage buckets.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars','avatars',true,5242880,array['image/jpeg','image/png','image/webp']::text[]),
  ('career-documents','career-documents',false,15728640,array['application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document','image/jpeg','image/png']::text[]),
  ('employer-documents','employer-documents',false,15728640,array['application/pdf','image/jpeg','image/png']::text[]),
  ('task-attachments','task-attachments',false,26214400,array['application/pdf','application/zip','text/plain','image/jpeg','image/png','application/vnd.openxmlformats-officedocument.wordprocessingml.document']::text[])
on conflict (id) do update set
  public=excluded.public,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

-- Internal authorization helpers for private storage buckets.
create or replace function private.can_read_candidate_document(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_owner_text text := (storage.foldername(p_name))[1];
begin
  if v_uid is null or v_owner_text is null then return false; end if;
  if v_owner_text = v_uid::text or private.is_admin_user() then return true; end if;
  return exists(
    select 1
    from public.profile_documents d
    where d.user_id::text=v_owner_text
      and d.file_url=p_name
      and d.is_public=true
      and (
        exists(
          select 1 from public.applications a
          join public.opportunities o on o.id=a.opportunity_id
          where a.applicant_id=d.user_id
            and o.employer_id is not null
            and private.has_employer_access(o.employer_id,false)
        )
        or exists(
          select 1 from public.saved_candidates s
          where s.candidate_id=d.user_id
            and private.has_employer_access(s.employer_id,false)
        )
      )
  );
end;
$$;

create or replace function private.can_access_employer_storage(p_name text, p_write boolean default false)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_employer_text text := (storage.foldername(p_name))[1];
begin
  if (select auth.uid()) is null or v_employer_text is null then return false; end if;
  return exists(
    select 1 from public.employers e
    where e.id::text=v_employer_text
      and private.has_employer_access(e.id,p_write)
  );
end;
$$;

create or replace function private.can_access_contract_storage(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_contract_text text := (storage.foldername(p_name))[1];
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null or v_contract_text is null then return false; end if;
  if private.is_admin_user() then return true; end if;
  return exists(
    select 1 from public.freelance_contracts c
    where c.id::text=v_contract_text
      and (
        c.freelancer_id=v_uid
        or (c.employer_id is not null and private.has_employer_access(c.employer_id,false))
      )
  );
end;
$$;

revoke all on function private.can_read_candidate_document(text) from public, anon;
revoke all on function private.can_access_employer_storage(text,boolean) from public, anon;
revoke all on function private.can_access_contract_storage(text) from public, anon;
grant execute on function private.can_read_candidate_document(text) to authenticated, service_role;
grant execute on function private.can_access_employer_storage(text,boolean) to authenticated, service_role;
grant execute on function private.can_access_contract_storage(text) to authenticated, service_role;

-- Replace only Mela-owned storage policies.
drop policy if exists "Mela avatar upload own folder" on storage.objects;
drop policy if exists "Mela avatar update own folder" on storage.objects;
drop policy if exists "Mela avatar delete own folder" on storage.objects;
drop policy if exists "Mela career docs read" on storage.objects;
drop policy if exists "Mela career docs upload own folder" on storage.objects;
drop policy if exists "Mela career docs update own folder" on storage.objects;
drop policy if exists "Mela career docs delete own folder" on storage.objects;
drop policy if exists "Mela employer docs read" on storage.objects;
drop policy if exists "Mela employer docs upload" on storage.objects;
drop policy if exists "Mela employer docs update" on storage.objects;
drop policy if exists "Mela employer docs delete" on storage.objects;
drop policy if exists "Mela task attachments read" on storage.objects;
drop policy if exists "Mela task attachments upload" on storage.objects;
drop policy if exists "Mela task attachments update" on storage.objects;
drop policy if exists "Mela task attachments delete" on storage.objects;

create policy "Mela avatar upload own folder" on storage.objects
for insert to authenticated
with check (bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Mela avatar update own folder" on storage.objects
for update to authenticated
using (bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text)
with check (bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Mela avatar delete own folder" on storage.objects
for delete to authenticated
using (bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);

create policy "Mela career docs read" on storage.objects
for select to authenticated
using (bucket_id='career-documents' and private.can_read_candidate_document(name));
create policy "Mela career docs upload own folder" on storage.objects
for insert to authenticated
with check (bucket_id='career-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Mela career docs update own folder" on storage.objects
for update to authenticated
using (bucket_id='career-documents' and (storage.foldername(name))[1]=(select auth.uid())::text)
with check (bucket_id='career-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Mela career docs delete own folder" on storage.objects
for delete to authenticated
using (bucket_id='career-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);

create policy "Mela employer docs read" on storage.objects
for select to authenticated
using (bucket_id='employer-documents' and private.can_access_employer_storage(name,false));
create policy "Mela employer docs upload" on storage.objects
for insert to authenticated
with check (bucket_id='employer-documents' and private.can_access_employer_storage(name,true));
create policy "Mela employer docs update" on storage.objects
for update to authenticated
using (bucket_id='employer-documents' and private.can_access_employer_storage(name,true))
with check (bucket_id='employer-documents' and private.can_access_employer_storage(name,true));
create policy "Mela employer docs delete" on storage.objects
for delete to authenticated
using (bucket_id='employer-documents' and private.can_access_employer_storage(name,true));

create policy "Mela task attachments read" on storage.objects
for select to authenticated
using (bucket_id='task-attachments' and private.can_access_contract_storage(name));
create policy "Mela task attachments upload" on storage.objects
for insert to authenticated
with check (bucket_id='task-attachments' and private.can_access_contract_storage(name));
create policy "Mela task attachments update" on storage.objects
for update to authenticated
using (bucket_id='task-attachments' and private.can_access_contract_storage(name))
with check (bucket_id='task-attachments' and private.can_access_contract_storage(name));
create policy "Mela task attachments delete" on storage.objects
for delete to authenticated
using (bucket_id='task-attachments' and private.can_access_contract_storage(name));

-- 2) Every new account gets notification preferences.
create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  insert into public.profiles (id, full_name, email, preferred_language)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name',''), nullif(split_part(coalesce(new.email,''),'@',1),''), 'Mela User'),
    coalesce(new.email,new.id::text || '@mela.invalid'),
    coalesce(nullif(new.raw_user_meta_data ->> 'preferred_language',''), nullif(new.raw_user_meta_data ->> 'language',''), 'English')
  )
  on conflict (id) do update set
    full_name=excluded.full_name,
    email=excluded.email,
    preferred_language=excluded.preferred_language,
    updated_at=now();

  insert into public.notification_preferences(user_id)
  values(new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

-- 3) Safe RPC for employer teams to refresh match scores.
create or replace function public.refresh_candidate_matches(p_opportunity_id uuid)
returns integer
language sql
security definer
set search_path=''
as $$
  select private.refresh_opportunity_candidate_matches(p_opportunity_id)
$$;
revoke all on function public.refresh_candidate_matches(uuid) from public, anon;
grant execute on function public.refresh_candidate_matches(uuid) to authenticated, service_role;

-- 4) Proctor event ingestion: client submits raw event metrics, server derives identity fields and flags.
alter table public.assessment_attempts add column if not exists reviewed_by uuid references public.profiles(id) on delete set null;
alter table public.assessment_attempts add column if not exists review_notes text;

alter table public.proctor_audit_logs drop constraint if exists proctor_face_confidence_chk;
alter table public.proctor_audit_logs add constraint proctor_face_confidence_chk check (face_detection_confidence is null or (face_detection_confidence>=0 and face_detection_confidence<=1));
alter table public.proctor_audit_logs drop constraint if exists proctor_tab_switch_chk;
alter table public.proctor_audit_logs add constraint proctor_tab_switch_chk check (tab_switch_count is null or tab_switch_count>=0);
alter table public.proctor_audit_logs drop constraint if exists proctor_event_type_chk;
alter table public.proctor_audit_logs add constraint proctor_event_type_chk check (event_type is null or event_type in ('camera_permission','identity_check','face_check','tab_switch','visibility_change','session_summary'));

create or replace function private.normalize_proctor_event()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_attempt_user uuid;
  v_title text;
  v_status text;
begin
  if new.attempt_id is null then raise exception 'attempt_id is required'; end if;
  select a.user_id, sa.title, a.status
    into v_attempt_user, v_title, v_status
  from public.assessment_attempts a
  join public.skill_assessments sa on sa.id=a.assessment_id
  where a.id=new.attempt_id and a.proctored=true;
  if not found then raise exception 'proctored assessment attempt not found'; end if;
  if (select auth.uid()) is not null and (select auth.uid())<>v_attempt_user then raise exception 'not authorized for this attempt'; end if;
  if v_status not in ('in_progress','submitted','review_required') then raise exception 'attempt is not accepting proctor events'; end if;

  new.user_id := v_attempt_user;
  new.assessment_title := v_title;
  new.audit_timestamp := now();
  new.tab_switch_count := greatest(coalesce(new.tab_switch_count,0),0);
  new.flagged := (coalesce(new.face_detection_confidence,1)<0.70 or new.tab_switch_count>3);
  new.flagged_reason := case
    when coalesce(new.face_detection_confidence,1)<0.70 and new.tab_switch_count>3 then 'low_face_confidence_and_excessive_tab_switching'
    when coalesce(new.face_detection_confidence,1)<0.70 then 'low_face_confidence'
    when new.tab_switch_count>3 then 'excessive_tab_switching'
    else null end;
  return new;
end;
$$;

drop trigger if exists trg_normalize_proctor_event on public.proctor_audit_logs;
create trigger trg_normalize_proctor_event
before insert or update on public.proctor_audit_logs
for each row execute function private.normalize_proctor_event();

drop policy if exists "Students submit own proctor events" on public.proctor_audit_logs;
create policy "Students submit own proctor events" on public.proctor_audit_logs
for insert to authenticated
with check (
  user_id=(select auth.uid())
  and exists(select 1 from public.assessment_attempts a where a.id=attempt_id and a.user_id=(select auth.uid()) and a.proctored=true)
);

revoke insert, update, delete on public.proctor_audit_logs from authenticated;
grant insert (attempt_id,event_type,face_detection_confidence,tab_switch_count,details) on public.proctor_audit_logs to authenticated;

create or replace function public.review_proctored_attempt(p_attempt_id uuid, p_decision text, p_notes text default null)
returns public.assessment_attempts
language plpgsql
security definer
set search_path=''
as $$
declare
  v_row public.assessment_attempts%rowtype;
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
  if p_decision not in ('clear','void') then raise exception 'decision must be clear or void'; end if;
  select * into v_row from public.assessment_attempts where id=p_attempt_id for update;
  if not found or not v_row.proctored then raise exception 'proctored attempt not found'; end if;
  if v_row.score is null then raise exception 'attempt has not been graded'; end if;

  update public.assessment_attempts
     set proctor_status=case when p_decision='clear' then 'clear' else 'flagged' end,
         status=case when p_decision='clear' then 'graded' else 'void' end,
         reviewed_by=v_uid,
         reviewed_at=now(),
         review_notes=nullif(trim(coalesce(p_notes,'')),'')
   where id=p_attempt_id
   returning * into v_row;

  if p_decision='clear' then perform private.issue_assessment_verified_skill(p_attempt_id); end if;
  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
  values(v_uid,'review_proctored_attempt','assessment_attempt',p_attempt_id,jsonb_build_object('decision',p_decision,'notes',p_notes));
  return v_row;
end;
$$;
revoke all on function public.review_proctored_attempt(uuid,text,text) from public, anon;
grant execute on function public.review_proctored_attempt(uuid,text,text) to authenticated, service_role;

-- 5) Least-privilege grants for internal/audit tables.
revoke insert, update, delete on public.admin_audit_logs from authenticated;
revoke update, delete on public.platform_events from authenticated;
revoke update on public.notifications from authenticated;
grant update (is_read) on public.notifications to authenticated;

;

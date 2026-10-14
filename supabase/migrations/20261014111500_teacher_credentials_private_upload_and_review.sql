-- MELA protected teacher credential submission and verified administrator review
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('teacher-credentials','teacher-credentials',false,10485760,
  array['application/pdf','image/jpeg','image/png'])
on conflict(id) do update set public=false,file_size_limit=10485760,
  allowed_mime_types=excluded.allowed_mime_types;

create table if not exists public.teacher_credential_documents(
 id uuid primary key default gen_random_uuid(),
 teacher_id uuid not null references public.teacher_profiles(user_id) on delete cascade,
 document_kind text not null check(document_kind in ('degree','diploma','teaching_license','professional_certificate','other')),
 original_name text not null check(char_length(original_name) between 3 and 180),
 storage_path text not null unique,
 review_status text not null default 'pending' check(review_status in ('pending','approved','rejected')),
 review_note text,
 reviewed_by uuid references auth.users(id),
 reviewed_at timestamptz,
 uploaded_at timestamptz not null default now(),
 constraint teacher_credential_path_matches_id check(
  storage_path ~ ('^' || teacher_id::text || '/' || id::text || '[.](pdf|jpg|jpeg|png)$')
 )
);
create index if not exists teacher_credential_docs_queue_idx on public.teacher_credential_documents(review_status,uploaded_at);
create index if not exists teacher_credential_docs_owner_idx on public.teacher_credential_documents(teacher_id,uploaded_at desc);
alter table public.teacher_credential_documents enable row level security;
revoke all on public.teacher_credential_documents from PUBLIC,anon,authenticated;
grant select on public.teacher_credential_documents to authenticated;
grant insert(id,teacher_id,document_kind,original_name,storage_path) on public.teacher_credential_documents to authenticated;
drop policy if exists teacher_credential_docs_read on public.teacher_credential_documents;
create policy teacher_credential_docs_read on public.teacher_credential_documents
for select to authenticated using(teacher_id=(select auth.uid()) or private.is_admin_user());
drop policy if exists teacher_credential_docs_insert on public.teacher_credential_documents;
create policy teacher_credential_docs_insert on public.teacher_credential_documents
for insert to authenticated with check(
 teacher_id=(select auth.uid()) and review_status='pending'
 and exists(select 1 from public.profiles p where p.id=(select auth.uid())
   and p.role='teacher' and p.account_status='active' and p.email_verified
   and p.role_selected_at is not null)
);
create or replace function private.validate_teacher_credential_metadata()
returns trigger language plpgsql security definer set search_path to ''
as $function$
declare existing_count int;
begin
 if new.teacher_id is distinct from (select auth.uid()) then
  raise exception 'document owner mismatch' using errcode='42501';
 end if;
 select count(*) into existing_count from public.teacher_credential_documents where teacher_id=new.teacher_id;
 if existing_count>=12 then raise exception 'maximum twelve credential documents'; end if;
 if not exists(select 1 from storage.objects o
   where o.bucket_id='teacher-credentials' and o.name=new.storage_path and o.owner_id=new.teacher_id::text
     and (o.metadata->>'mimetype') in ('application/pdf','image/jpeg','image/png')
     and (o.metadata->>'size')::bigint between 1 and 10485760) then
    raise exception 'credential file is missing or invalid';
 end if;
 return new;
end $function$;
drop trigger if exists validate_teacher_credential_document_insert on public.teacher_credential_documents;
create trigger validate_teacher_credential_document_insert before insert
on public.teacher_credential_documents for each row
execute function private.validate_teacher_credential_metadata();

-- Existing permissive all-bucket storage policies require restrictive
-- checks to prevent any other authenticated user viewing this bucket.
drop policy if exists tc_restrict_select on storage.objects;
create policy tc_restrict_select on storage.objects as restrictive
for select to authenticated using (
 bucket_id <> 'teacher-credentials' or
 ( (storage.foldername(name))[1]=(select auth.uid())::text or private.is_admin_user() )
);
drop policy if exists tc_restrict_insert on storage.objects;
create policy tc_restrict_insert on storage.objects as restrictive
for insert to authenticated with check (
 bucket_id <> 'teacher-credentials' or (
 (storage.foldername(name))[1]=(select auth.uid())::text
 and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f-]{36}[.](pdf|jpg|jpeg|png)$')
 and exists(select 1 from public.profiles p where p.id=(select auth.uid())
     and p.role='teacher' and p.account_status='active' and p.email_verified)
 ));
drop policy if exists tc_restrict_update on storage.objects;
create policy tc_restrict_update on storage.objects as restrictive
for update to authenticated using (bucket_id <> 'teacher-credentials')
with check (bucket_id <> 'teacher-credentials');
drop policy if exists tc_restrict_delete on storage.objects;
create policy tc_restrict_delete on storage.objects as restrictive
for delete to authenticated using (bucket_id <> 'teacher-credentials');

drop policy if exists tc_owner_read on storage.objects;
create policy tc_owner_read on storage.objects
for select to authenticated using(bucket_id='teacher-credentials' and
 ((storage.foldername(name))[1]=(select auth.uid())::text or private.is_admin_user()));
drop policy if exists tc_owner_insert on storage.objects;
create policy tc_owner_insert on storage.objects
for insert to authenticated with check(bucket_id='teacher-credentials' and
 (storage.foldername(name))[1]=(select auth.uid())::text
 and exists(select 1 from public.profiles p where p.id=(select auth.uid())
     and p.role='teacher' and p.account_status='active' and p.email_verified));

create or replace function private.review_teacher_credential_document(
 p_document_id uuid,p_decision text,p_note text)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare actor uuid:=(select auth.uid()); prior public.teacher_credential_documents%rowtype;
 final public.teacher_credential_documents%rowtype; explanation text:=btrim(coalesce(p_note,''));
begin
 if actor is null or not private.is_admin_user() then
  raise exception 'MFA administrator authorization required' using errcode='42501';
 end if;
 if p_decision not in ('approved','rejected') then raise exception 'invalid credential decision'; end if;
 if char_length(explanation)<8 or char_length(explanation)>2000 then
   raise exception 'explain evidence checks in 8-2000 characters';
 end if;
 select * into prior from public.teacher_credential_documents where id=p_document_id for update;
 if not found then raise exception 'credential not found'; end if;
 if not exists(select 1 from storage.objects
   where bucket_id='teacher-credentials' and name=prior.storage_path and owner_id=prior.teacher_id::text)
 then raise exception 'credential file is missing'; end if;
 update public.teacher_credential_documents set review_status=p_decision,
   review_note=explanation,reviewed_by=actor,reviewed_at=now()
 where id=p_document_id returning * into final;
 insert into admin.audit_log(actor_user_id,actor_role,action,target_schema,target_table,target_id,before_data,after_data,metadata)
 values(actor,'admin','teacher.credential.review','public','teacher_credential_documents',
   p_document_id::text,to_jsonb(prior),to_jsonb(final),jsonb_build_object('decision',p_decision));
 return jsonb_build_object('document_id',final.id,'status',final.review_status);
end $function$;
create or replace function public.review_teacher_credential_document(p_document_id uuid,p_decision text,p_note text)
returns jsonb language sql set search_path to ''
as $function$ select private.review_teacher_credential_document(p_document_id,p_decision,p_note); $function$;
revoke all on function public.review_teacher_credential_document(uuid,text,text) from PUBLIC,anon;
grant execute on function public.review_teacher_credential_document(uuid,text,text) to authenticated;

-- Guard both administrative teacher approval and all teacher content-review RPCs.
CREATE OR REPLACE FUNCTION private.review_teacher_profile(p_user_id uuid, p_decision text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_note text := btrim(coalesce(p_note,''));
  v_before public.teacher_profiles%rowtype;
  v_after public.teacher_profiles%rowtype;
begin
  if not private.is_admin_user() or v_actor is null then raise exception 'admin authorization with MFA required' using errcode='42501'; end if;
  if p_decision not in ('approved','rejected','suspended') then raise exception 'invalid teacher verification decision'; end if;
  if char_length(v_note)<5 or char_length(v_note)>4000 then raise exception 'verification note must be 5-4000 characters'; end if;

  select * into v_before from public.teacher_profiles where user_id=p_user_id for update;
  if not found then raise exception 'teacher profile not found'; end if;
  if p_decision='approved' then
    if not exists(select 1 from public.teacher_credential_documents d
      where d.teacher_id=p_user_id and d.review_status='approved') then
      raise exception 'approve at least one independently verified qualification document before approving teacher';
    end if;
    if coalesce(char_length(btrim(v_before.qualification)),0)<2 then raise exception 'qualification is required before approval'; end if;
    if coalesce(cardinality(v_before.subjects_taught),0)=0 then raise exception 'at least one teaching subject is required before approval'; end if;
    if coalesce(cardinality(v_before.grade_levels),0)=0 then raise exception 'at least one grade level is required before approval'; end if;
    if coalesce(char_length(btrim(v_before.institution)),0)<2 then raise exception 'institution is required before approval'; end if;
  end if;

  update public.teacher_profiles
  set verification_status=p_decision,
      verification_notes=v_note,
      verified_by=v_actor,
      verified_at=case when p_decision='approved' then now() else null end,
      updated_at=now()
  where user_id=p_user_id
  returning * into v_after;

  if p_decision='approved' then
    insert into private.educator_review_authorizations(user_id,subject_areas,active,granted_by,grant_note,granted_at,updated_at)
    values(p_user_id,v_after.subjects_taught,true,v_actor,v_note,now(),now())
    on conflict(user_id) do update set subject_areas=excluded.subject_areas,active=true,granted_by=excluded.granted_by,grant_note=excluded.grant_note,granted_at=now(),updated_at=now();
  else
    update private.educator_review_authorizations set active=false,updated_at=now(),granted_by=v_actor,grant_note=v_note where user_id=p_user_id;
    update public.educator_profiles set active=false,updated_at=now() where user_id=p_user_id;
  end if;

  insert into admin.audit_log(actor_user_id,actor_role,action,target_schema,target_table,target_id,before_data,after_data,metadata)
  values(v_actor,'admin','teacher.verification.review','public','teacher_profiles',p_user_id::text,to_jsonb(v_before),to_jsonb(v_after),jsonb_build_object('decision',p_decision,'review_authorization_active',p_decision='approved'));

  return jsonb_build_object('user_id',p_user_id,'verification_status',p_decision,'review_authorized',p_decision='approved','subject_areas',v_after.subjects_taught,'verified_at',v_after.verified_at);
end;
$function$;


CREATE OR REPLACE FUNCTION private.question_reviewer_allowed_v18(p_uid uuid, p_program_key text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select (
    p_uid = (select auth.uid()) and private.is_admin_user()
  ) or (
    p_uid = (select auth.uid()) and exists(
      select 1
      from public.teacher_profiles t
      join public.mela_learning_programs lp on lp.program_key = p_program_key
      where t.user_id = p_uid
        and t.verification_status = 'approved'
        and exists(select 1 from public.teacher_credential_documents d
          where d.teacher_id=t.user_id and d.review_status='approved')
        -- Only exact subject names/keys, ignoring case and surrounding spaces.
        and exists(
          select 1 from unnest(coalesce(t.subjects_taught, '{}'::text[])) s(subject)
          where lower(btrim(s.subject)) = lower(btrim(lp.subject_key))
             or lower(btrim(s.subject)) = lower(btrim(lp.subject_title))
        )
        -- School teachers: verified grade number; university/TVET: verified stage.
        and exists(
          select 1 from unnest(coalesce(t.grade_levels, '{}'::text[])) g(level)
          where lower(btrim(g.level)) = coalesce(lp.grade_level::text, lower(btrim(lp.stage_key)))
        )
        -- Independent authorization remains mandatory; submitting a profile
        -- or editing any education fields does not grant reviewer access.
        and (
          exists(
            select 1 from private.educator_review_authorizations a
            where a.user_id = p_uid and a.active
              and exists(
                select 1 from unnest(coalesce(a.subject_areas, '{}'::text[])) allowed(subject)
                where lower(btrim(allowed.subject)) = lower(btrim(lp.subject_key))
                   or lower(btrim(allowed.subject)) = lower(btrim(lp.subject_title))
              )
          )
          or exists(
            select 1 from public.educator_profiles e
            where e.user_id = p_uid and e.verified and e.active
              and exists(
                select 1 from unnest(coalesce(e.subject_areas, '{}'::text[])) allowed(subject)
                where lower(btrim(allowed.subject)) = lower(btrim(lp.subject_key))
                   or lower(btrim(allowed.subject)) = lower(btrim(lp.subject_title))
              )
          )
        )
    )
  );
$function$;

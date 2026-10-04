-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812214306
-- Admin verification/moderation layer for Career Passport, employers and reports.

-- Verification metadata.
alter table public.profile_documents add column if not exists verification_source text;
alter table public.profile_documents add column if not exists verification_notes text;
alter table public.profile_documents add column if not exists verified_at timestamptz;
alter table public.profile_documents add column if not exists verified_by uuid references public.profiles(id) on delete set null;

alter table public.profile_education add column if not exists verification_notes text;
alter table public.profile_education add column if not exists verified_at timestamptz;
alter table public.profile_education add column if not exists verified_by uuid references public.profiles(id) on delete set null;

alter table public.profile_experience add column if not exists verification_notes text;
alter table public.profile_experience add column if not exists verified_at timestamptz;
alter table public.profile_experience add column if not exists verified_by uuid references public.profiles(id) on delete set null;

alter table public.profile_languages add column if not exists verification_source text;
alter table public.profile_languages add column if not exists verification_notes text;
alter table public.profile_languages add column if not exists verified_at timestamptz;
alter table public.profile_languages add column if not exists verified_by uuid references public.profiles(id) on delete set null;

-- Admin-aware protection triggers.
create or replace function private.protect_document_verification()
returns trigger language plpgsql set search_path=''
as $$
declare v_admin boolean:=false;
begin
  if (select auth.uid()) is not null then
    v_admin:=private.is_admin_user();
    if tg_op='INSERT' then
      new.verified:=false; new.verification_source:=null; new.verification_notes:=null; new.verified_at:=null; new.verified_by:=null;
    elsif not v_admin and (
      new.verified is distinct from old.verified or new.verification_source is distinct from old.verification_source or
      new.verification_notes is distinct from old.verification_notes or new.verified_at is distinct from old.verified_at or new.verified_by is distinct from old.verified_by
    ) then raise exception 'document verification is admin managed';
    elsif v_admin and new.verified is distinct from old.verified then
      new.verified_by:=(select auth.uid()); new.verified_at:=now();
    end if;
  end if;
  return new;
end;
$$;

create or replace function private.protect_education_verification()
returns trigger language plpgsql set search_path=''
as $$
declare v_admin boolean:=false;
begin
  if (select auth.uid()) is not null then
    v_admin:=private.is_admin_user();
    if tg_op='INSERT' then
      new.verified:=false; new.verification_source:=null; new.verification_notes:=null; new.verified_at:=null; new.verified_by:=null;
    elsif not v_admin and (
      new.verified is distinct from old.verified or new.verification_source is distinct from old.verification_source or
      new.verification_notes is distinct from old.verification_notes or new.verified_at is distinct from old.verified_at or new.verified_by is distinct from old.verified_by
    ) then raise exception 'education verification is admin managed';
    elsif v_admin and new.verified is distinct from old.verified then
      new.verified_by:=(select auth.uid()); new.verified_at:=now();
    end if;
  end if;
  new.updated_at:=now(); return new;
end;
$$;

create or replace function private.protect_experience_verification()
returns trigger language plpgsql set search_path=''
as $$
declare v_admin boolean:=false;
begin
  if (select auth.uid()) is not null then
    v_admin:=private.is_admin_user();
    if tg_op='INSERT' then
      new.verified:=false; new.verification_source:=null; new.verification_notes:=null; new.verified_at:=null; new.verified_by:=null;
    elsif not v_admin and (
      new.verified is distinct from old.verified or new.verification_source is distinct from old.verification_source or
      new.verification_notes is distinct from old.verification_notes or new.verified_at is distinct from old.verified_at or new.verified_by is distinct from old.verified_by
    ) then raise exception 'experience verification is admin managed';
    elsif v_admin and new.verified is distinct from old.verified then
      new.verified_by:=(select auth.uid()); new.verified_at:=now();
    end if;
  end if;
  new.updated_at:=now(); return new;
end;
$$;

create or replace function private.protect_language_verification()
returns trigger language plpgsql set search_path=''
as $$
declare v_admin boolean:=false;
begin
  if (select auth.uid()) is not null then
    v_admin:=private.is_admin_user();
    if tg_op='INSERT' then
      new.verified:=false; new.verification_source:=null; new.verification_notes:=null; new.verified_at:=null; new.verified_by:=null;
    elsif not v_admin and (
      new.verified is distinct from old.verified or new.verification_source is distinct from old.verification_source or
      new.verification_notes is distinct from old.verification_notes or new.verified_at is distinct from old.verified_at or new.verified_by is distinct from old.verified_by
    ) then raise exception 'language verification is admin managed';
    elsif v_admin and new.verified is distinct from old.verified then
      new.verified_by:=(select auth.uid()); new.verified_at:=now();
    end if;
  end if;
  return new;
end;
$$;

-- Least privilege for user-editable Career Passport rows.
revoke update on public.profile_documents from authenticated;
grant update (document_type,title,file_url,issuer,issued_on,expires_on,is_public) on public.profile_documents to authenticated;
revoke update on public.profile_education from authenticated;
grant update (institution,qualification,field_of_study,start_year,end_year,is_current,grade,description,is_public) on public.profile_education to authenticated;
revoke update on public.profile_experience from authenticated;
grant update (organization,title,experience_type,start_date,end_date,is_current,description,is_public) on public.profile_experience to authenticated;
revoke update on public.profile_languages from authenticated;
grant update (language,proficiency) on public.profile_languages to authenticated;

-- Employer registration: applicants edit only application data, admin decisions use RPC.
revoke update on public.employer_registration_requests from authenticated;
grant update (company_name,legal_name,registration_number,industry,sector_category,website,contact_email,phone_number,headquarters,description) on public.employer_registration_requests to authenticated;

-- Employer verification document: owners can replace/edit file metadata, review fields are RPC/admin only.
revoke update on public.employer_verification_documents from authenticated;
grant update (document_type,file_path,display_name) on public.employer_verification_documents to authenticated;

-- Employer profile: normal editable business fields only.
revoke update on public.employers from authenticated;
grant update (
  company_name,industry,website,description,logo_url,contact_email,phone_number,headquarters,sector_category,
  legal_name,registration_number,company_size,founded_year,address_line,city,country,careers_url,linkedin_url,hiring_email,hiring_phone
) on public.employers to authenticated;

-- Reports are submitted/read directly; moderation uses RPC.
revoke update, delete on public.reports from authenticated;

-- Admin RPC: employer registration request review.
create or replace function public.review_employer_registration(p_request_id uuid,p_decision text,p_notes text default null)
returns public.employer_registration_requests
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_row public.employer_registration_requests%rowtype;
begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
  if p_decision not in ('under_review','approved','rejected') then raise exception 'invalid decision'; end if;
  select * into v_row from public.employer_registration_requests where id=p_request_id for update;
  if not found then raise exception 'registration request not found'; end if;
  if v_row.status not in ('pending','under_review') then raise exception 'request is already finalized'; end if;
  update public.employer_registration_requests set status=p_decision,review_notes=nullif(trim(coalesce(p_notes,'')),'') where id=p_request_id returning * into v_row;
  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
  values(v_uid,'review_employer_registration','employer_registration_request',p_request_id,jsonb_build_object('decision',p_decision,'notes',p_notes));
  insert into public.notifications(user_id,title,body,ref_table,ref_id)
  values(v_row.applicant_user_id,'Employer registration update','Your employer registration is now '||p_decision||'.','employer_registration_requests',v_row.id);
  return v_row;
end;
$$;

-- Admin RPC: verification document review.
create or replace function public.review_employer_document(p_document_id uuid,p_decision text,p_notes text default null)
returns public.employer_verification_documents
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_row public.employer_verification_documents%rowtype; v_owner uuid;
begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
  if p_decision not in ('accepted','rejected') then raise exception 'decision must be accepted or rejected'; end if;
  update public.employer_verification_documents set review_status=p_decision,review_notes=nullif(trim(coalesce(p_notes,'')),'') where id=p_document_id returning * into v_row;
  if not found then raise exception 'verification document not found'; end if;
  select owner_id into v_owner from public.employers where id=v_row.employer_id;
  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
  values(v_uid,'review_employer_document','employer_verification_document',p_document_id,jsonb_build_object('decision',p_decision,'notes',p_notes));
  if v_owner is not null then insert into public.notifications(user_id,title,body,ref_table,ref_id) values(v_owner,'Verification document reviewed','An employer verification document was '||p_decision||'.','employer_verification_documents',v_row.id); end if;
  return v_row;
end;
$$;

-- Admin RPC: company verification status.
create or replace function public.review_employer_verification(p_employer_id uuid,p_status text,p_notes text default null)
returns public.employers
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_row public.employers%rowtype;
begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
  if p_status not in ('under_review','verified','rejected','suspended') then raise exception 'invalid employer verification status'; end if;
  update public.employers
     set verification_status=p_status,verified=(p_status='verified'),verified_at=case when p_status='verified' then now() else null end,verification_notes=nullif(trim(coalesce(p_notes,'')),'')
   where id=p_employer_id returning * into v_row;
  if not found then raise exception 'employer not found'; end if;
  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
  values(v_uid,'review_employer_verification','employer',p_employer_id,jsonb_build_object('status',p_status,'notes',p_notes));
  insert into public.notifications(user_id,title,body,ref_table,ref_id)
  values(v_row.owner_id,'Employer verification update','Your organization verification is now '||p_status||'.','employers',v_row.id);
  return v_row;
end;
$$;

-- Generic auditable Career Passport verification RPCs.
create or replace function public.review_profile_document(p_document_id uuid,p_verified boolean,p_source text default null,p_notes text default null)
returns public.profile_documents language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_row public.profile_documents%rowtype;
begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
  update public.profile_documents set verified=p_verified,verification_source=nullif(trim(coalesce(p_source,'')),''),verification_notes=nullif(trim(coalesce(p_notes,'')),'') where id=p_document_id returning * into v_row;
  if not found then raise exception 'document not found'; end if;
  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details) values(v_uid,'review_profile_document','profile_document',p_document_id,jsonb_build_object('verified',p_verified,'source',p_source,'notes',p_notes));
  insert into public.notifications(user_id,title,body,ref_table,ref_id) values(v_row.user_id,'Career Passport document reviewed',case when p_verified then 'A Career Passport document was verified.' else 'A Career Passport document verification was declined.' end,'profile_documents',v_row.id);
  return v_row;
end;
$$;

create or replace function public.review_profile_education(p_education_id uuid,p_verified boolean,p_source text default null,p_notes text default null)
returns public.profile_education language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_row public.profile_education%rowtype;
begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
  update public.profile_education set verified=p_verified,verification_source=nullif(trim(coalesce(p_source,'')),''),verification_notes=nullif(trim(coalesce(p_notes,'')),'') where id=p_education_id returning * into v_row;
  if not found then raise exception 'education record not found'; end if;
  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details) values(v_uid,'review_profile_education','profile_education',p_education_id,jsonb_build_object('verified',p_verified,'source',p_source,'notes',p_notes));
  insert into public.notifications(user_id,title,body,ref_table,ref_id) values(v_row.user_id,'Education record reviewed',case when p_verified then 'An education record was verified.' else 'An education record verification was declined.' end,'profile_education',v_row.id);
  return v_row;
end;
$$;

create or replace function public.review_profile_experience(p_experience_id uuid,p_verified boolean,p_source text default null,p_notes text default null)
returns public.profile_experience language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_row public.profile_experience%rowtype;
begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
  update public.profile_experience set verified=p_verified,verification_source=nullif(trim(coalesce(p_source,'')),''),verification_notes=nullif(trim(coalesce(p_notes,'')),'') where id=p_experience_id returning * into v_row;
  if not found then raise exception 'experience record not found'; end if;
  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details) values(v_uid,'review_profile_experience','profile_experience',p_experience_id,jsonb_build_object('verified',p_verified,'source',p_source,'notes',p_notes));
  insert into public.notifications(user_id,title,body,ref_table,ref_id) values(v_row.user_id,'Experience record reviewed',case when p_verified then 'An experience record was verified.' else 'An experience record verification was declined.' end,'profile_experience',v_row.id);
  return v_row;
end;
$$;

create or replace function public.review_profile_language(p_language_id uuid,p_verified boolean,p_source text default null,p_notes text default null)
returns public.profile_languages language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_row public.profile_languages%rowtype;
begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
  update public.profile_languages set verified=p_verified,verification_source=nullif(trim(coalesce(p_source,'')),''),verification_notes=nullif(trim(coalesce(p_notes,'')),'') where id=p_language_id returning * into v_row;
  if not found then raise exception 'language record not found'; end if;
  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details) values(v_uid,'review_profile_language','profile_language',p_language_id,jsonb_build_object('verified',p_verified,'source',p_source,'notes',p_notes));
  insert into public.notifications(user_id,title,body,ref_table,ref_id) values(v_row.user_id,'Language record reviewed',case when p_verified then 'A language record was verified.' else 'A language record verification was declined.' end,'profile_languages',v_row.id);
  return v_row;
end;
$$;

-- Admin report triage/resolution.
create or replace function public.review_report(p_report_id uuid,p_status text,p_notes text default null,p_assigned_to uuid default null)
returns public.reports language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_row public.reports%rowtype;
begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
  if p_status not in ('open','reviewing','resolved','dismissed') then raise exception 'invalid report status'; end if;
  if p_assigned_to is not null and not exists(select 1 from public.profiles p where p.id=p_assigned_to and p.role='admin'::public.user_role) then raise exception 'assignee must be an admin'; end if;
  update public.reports
     set status=p_status,assigned_to=coalesce(p_assigned_to,assigned_to),resolution_notes=nullif(trim(coalesce(p_notes,'')),''),resolved_at=case when p_status in ('resolved','dismissed') then now() else null end
   where id=p_report_id returning * into v_row;
  if not found then raise exception 'report not found'; end if;
  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details) values(v_uid,'review_report','report',p_report_id,jsonb_build_object('status',p_status,'notes',p_notes,'assigned_to',p_assigned_to));
  if v_row.reporter_id is not null then insert into public.notifications(user_id,title,body,ref_table,ref_id) values(v_row.reporter_id,'Report status update','Your report is now '||p_status||'.','reports',v_row.id); end if;
  return v_row;
end;
$$;

-- Lock down all new privileged RPCs.
revoke all on function public.review_employer_registration(uuid,text,text) from public,anon;
revoke all on function public.review_employer_document(uuid,text,text) from public,anon;
revoke all on function public.review_employer_verification(uuid,text,text) from public,anon;
revoke all on function public.review_profile_document(uuid,boolean,text,text) from public,anon;
revoke all on function public.review_profile_education(uuid,boolean,text,text) from public,anon;
revoke all on function public.review_profile_experience(uuid,boolean,text,text) from public,anon;
revoke all on function public.review_profile_language(uuid,boolean,text,text) from public,anon;
revoke all on function public.review_report(uuid,text,text,uuid) from public,anon;
grant execute on function public.review_employer_registration(uuid,text,text) to authenticated,service_role;
grant execute on function public.review_employer_document(uuid,text,text) to authenticated,service_role;
grant execute on function public.review_employer_verification(uuid,text,text) to authenticated,service_role;
grant execute on function public.review_profile_document(uuid,boolean,text,text) to authenticated,service_role;
grant execute on function public.review_profile_education(uuid,boolean,text,text) to authenticated,service_role;
grant execute on function public.review_profile_experience(uuid,boolean,text,text) to authenticated,service_role;
grant execute on function public.review_profile_language(uuid,boolean,text,text) to authenticated,service_role;
grant execute on function public.review_report(uuid,text,text,uuid) to authenticated,service_role;

;

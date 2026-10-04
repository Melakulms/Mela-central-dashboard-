-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812214721
-- Preserve reviewer identity when admin actions are performed through server-side Edge Functions.
alter table public.employers add column if not exists verified_by uuid references public.profiles(id) on delete set null;

create or replace function private.process_employer_registration_request()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare v_uid uuid:=(select auth.uid()); v_admin boolean:=false; v_employer_id uuid; v_server boolean:=current_user in ('service_role','postgres');
begin
  if v_uid is not null then select exists(select 1 from public.profiles p where p.id=v_uid and p.role='admin'::public.user_role) into v_admin; end if;
  if tg_op='UPDATE' and not v_admin and not v_server and v_uid is not null then
    if new.status is distinct from old.status or new.review_notes is distinct from old.review_notes or new.reviewed_by is distinct from old.reviewed_by or new.reviewed_at is distinct from old.reviewed_at or new.employer_id is distinct from old.employer_id then raise exception 'review fields are admin managed'; end if;
    if old.status not in ('pending','under_review') then raise exception 'request can no longer be edited'; end if;
  end if;
  new.updated_at:=now();
  if tg_op='UPDATE' and new.status in ('approved','rejected') and new.status is distinct from old.status then new.reviewed_by:=coalesce(v_uid,new.reviewed_by); new.reviewed_at:=now(); end if;
  if tg_op='UPDATE' and new.status='approved' and old.status is distinct from 'approved' then
    update public.profiles set role='employer'::public.user_role where id=new.applicant_user_id;
    if new.employer_id is null then
      insert into public.employers(owner_id,company_name,legal_name,registration_number,industry,sector_category,website,contact_email,phone_number,headquarters,description,verified,verification_status)
      values(new.applicant_user_id,new.company_name,new.legal_name,new.registration_number,new.industry,new.sector_category,new.website,new.contact_email,new.phone_number,new.headquarters,new.description,false,'pending')
      returning id into v_employer_id; new.employer_id:=v_employer_id;
    end if;
  end if;
  return new;
end;$$;
revoke all on function private.process_employer_registration_request() from public,anon,authenticated;

create or replace function private.audit_employer_registration_change()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
begin
  if new.status is distinct from old.status and new.status in ('approved','rejected') then
    insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
    values(coalesce((select auth.uid()),new.reviewed_by),'employer_registration_'||new.status,'employer_registration_request',new.id,jsonb_build_object('company_name',new.company_name,'employer_id',new.employer_id));
    perform private.create_notification(new.applicant_user_id,'Employer registration '||new.status,case when new.status='approved' then 'Your organization registration was approved.' else coalesce(new.review_notes,'Your organization registration was not approved.') end,'employer_registration_requests',new.id);
  end if; return new;
end;$$;

create or replace function private.protect_employer_verification_fields()
returns trigger language plpgsql set search_path='pg_catalog','public','private' as $$
declare v_uid uuid:=(select auth.uid()); v_admin boolean:=false; v_server boolean:=current_user in ('service_role','postgres');
begin
  if v_uid is not null then select exists(select 1 from public.profiles p where p.id=v_uid and p.role='admin'::public.user_role) into v_admin; end if;
  if not v_admin and not v_server and v_uid is not null and (
    new.verified is distinct from old.verified or new.verification_status is distinct from old.verification_status or new.verified_at is distinct from old.verified_at or new.verified_by is distinct from old.verified_by or new.verification_notes is distinct from old.verification_notes
  ) then raise exception 'employer verification fields are admin managed'; end if;
  if (v_admin or v_server) and (new.verified is distinct from old.verified or new.verification_status is distinct from old.verification_status) then new.verified_by:=coalesce(v_uid,new.verified_by); new.verified_at:=now(); end if;
  new.updated_at:=now(); return new;
end;$$;

create or replace function private.audit_employer_verification_change()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
begin
  if new.verified is distinct from old.verified or new.verification_status is distinct from old.verification_status then
    insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
    values(coalesce((select auth.uid()),new.verified_by),'employer_verification_changed','employer',new.id,jsonb_build_object('verified',new.verified,'verification_status',new.verification_status));
    perform private.create_notification(new.owner_id,'Employer verification update','Organization verification status: '||new.verification_status||'.','employers',new.id);
  end if; return new;
end;$$;

create or replace function private.protect_mentor_verification()
returns trigger language plpgsql set search_path='pg_catalog','public','private' as $$
declare v_uid uuid:=(select auth.uid()); v_admin boolean:=false; v_server boolean:=current_user in ('service_role','postgres');
begin
  if v_uid is not null then v_admin:=private.is_admin_user(); end if;
  if tg_op='INSERT' and not v_server then new.verified:=false; new.verified_at:=null; new.verified_by:=null; new.verification_notes:=null;
  elsif not v_admin and not v_server and v_uid is not null and (new.verified is distinct from old.verified or new.verified_at is distinct from old.verified_at or new.verified_by is distinct from old.verified_by or new.verification_notes is distinct from old.verification_notes) then raise exception 'mentor verification is admin managed';
  elsif (v_admin or v_server) and tg_op='UPDATE' and new.verified is distinct from old.verified then new.verified_by:=coalesce(v_uid,new.verified_by); new.verified_at:=now(); end if;
  new.updated_at:=now(); return new;
end;$$;

create or replace function private.process_mentor_verification()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare v_actor uuid:=coalesce((select auth.uid()),new.verified_by);
begin
  if new.verified is distinct from old.verified then
    if new.verified then
      update public.profiles set role='mentor'::public.user_role,updated_at=now() where id=new.user_id and role='student'::public.user_role;
      perform private.create_notification(new.user_id,'Mentor profile verified','Your Mela mentor profile is now verified and discoverable.','mentor_profiles',new.user_id);
      insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details) values(v_actor,'mentor_verified','mentor_profile',new.user_id,jsonb_build_object('verified',true));
    else
      update public.profiles set role='student'::public.user_role,updated_at=now() where id=new.user_id and role='mentor'::public.user_role;
      perform private.create_notification(new.user_id,'Mentor verification changed','Your mentor verification is no longer active.','mentor_profiles',new.user_id);
      insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details) values(v_actor,'mentor_unverified','mentor_profile',new.user_id,jsonb_build_object('verified',false));
    end if;
  end if; return new;
end;$$;

-- Browser clients cannot touch reviewer identity fields.
revoke update (verified,verification_status,verified_at,verified_by,verification_notes) on public.employers from authenticated;
revoke insert,update on public.mentor_profiles from authenticated;
grant insert (user_id,headline,bio,expertise,years_experience,organization,languages,active) on public.mentor_profiles to authenticated;
grant update (headline,bio,expertise,years_experience,organization,languages,active) on public.mentor_profiles to authenticated;
grant all on public.employers,public.mentor_profiles,public.employer_registration_requests to service_role;

;

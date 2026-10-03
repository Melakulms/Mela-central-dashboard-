create or replace function private.can_review_questions_v18()
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then return false; end if;
  return private.is_admin_user()
    or exists(
      select 1 from public.educator_profiles e
      where e.user_id=v_uid and e.verified and e.active
    );
end
$function$;

create or replace function private.question_reviewer_allowed_v18(p_uid uuid, p_program_key text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select (
    p_uid = (select auth.uid()) and private.is_admin_user()
  ) or exists(
    select 1
    from public.educator_profiles e
    join public.mela_learning_programs lp on lp.program_key=p_program_key
    where e.user_id=p_uid and e.verified and e.active
      and (
        lp.subject_key=any(coalesce(e.subject_areas,'{}'::text[]))
        or lp.subject_title=any(coalesce(e.subject_areas,'{}'::text[]))
      )
  );
$function$;

create or replace function private.can_view_classroom(p_classroom uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists(
    select 1 from public.educator_classrooms c
    where c.id=p_classroom and c.educator_id=p_user
  )
  or exists(
    select 1 from public.educator_classroom_members m
    where m.classroom_id=p_classroom and m.learner_id=p_user and m.status='active'
  )
  or (p_user=(select auth.uid()) and private.is_admin_user());
$function$;

create or replace function private.prepare_opportunity()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_company public.employers%rowtype;
  v_platform_admin boolean:=false;
  v_source_fresh boolean:=false;
begin
  new.updated_at:=now();
  if new.posted_by is null then new.posted_by:=(select auth.uid()); end if;

  if new.employer_id is not null then
    select * into v_company from public.employers where id=new.employer_id;
    if not found then raise exception 'employer not found'; end if;
    new.organization_name:=v_company.company_name;
    new.organization:=v_company.company_name;
    if new.logo_url is null then new.logo_url:=v_company.logo_url; end if;
    if new.sector_category is null then new.sector_category:=v_company.sector_category; end if;
    new.source_type:='employer';
    new.verified_active:=(new.moderation_status='approved' and new.status='open' and new.deadline>=current_date and v_company.verified=true and v_company.verification_status='verified');
  else
    v_platform_admin := private.is_admin_user()
      or exists(
        select 1
        from admin.admin_users au
        join public.profiles p on p.id=au.user_id
        where au.user_id=new.posted_by
          and au.active=true
          and p.account_status='active'
          and p.deleted_at is null
      );
    v_source_fresh:=(new.source_url is not null and new.source_url ~ '^https://' and new.source_verified_at is not null and new.source_verified_at>=now()-interval '30 days');
    if new.source_type='official_external' and new.external_url is null then new.external_url:=new.source_url; end if;
    if new.source_type='official_external' then new.application_method:='external'; end if;
    new.verified_active:=(v_platform_admin and new.source_type in ('official_external','platform_curated') and v_source_fresh and new.status='open' and new.deadline>=current_date);
  end if;

  if new.status='open' and (tg_op='INSERT' or old.status is distinct from 'open') then new.published_at:=coalesce(new.published_at,now()); end if;
  return new;
end
$function$;

create or replace function private.protect_employer_document_review()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_admin boolean := false;
  v_owner boolean := false;
begin
  if v_uid is not null then
    v_admin := private.is_admin_user();
    select exists(select 1 from public.employers e where e.id=old.employer_id and e.owner_id=v_uid) into v_owner;

    if not v_admin and (
      new.review_status is distinct from old.review_status or
      new.review_notes is distinct from old.review_notes or
      new.reviewed_by is distinct from old.reviewed_by or
      new.reviewed_at is distinct from old.reviewed_at or
      new.employer_id is distinct from old.employer_id or
      new.uploaded_by is distinct from old.uploaded_by
    ) then raise exception 'document review fields are admin managed'; end if;

    if v_owner and not v_admin and (
      new.document_type is distinct from old.document_type or
      new.file_path is distinct from old.file_path or
      new.display_name is distinct from old.display_name
    ) then
      new.review_status := 'pending';
      new.review_notes := null;
      new.reviewed_by := null;
      new.reviewed_at := null;
    end if;
  end if;

  if tg_op='UPDATE' and new.review_status is distinct from old.review_status and v_admin then
    new.reviewed_by := v_uid;
    new.reviewed_at := now();
  end if;
  new.updated_at := now();
  return new;
end;
$function$;

create or replace function private.protect_employer_member_identity_fields()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_admin boolean := false;
  v_server boolean := current_user in ('service_role','postgres');
begin
  if v_uid is not null then v_admin := private.is_admin_user(); end if;
  if not v_admin and not v_server then
    if new.employer_id is distinct from old.employer_id or new.user_id is distinct from old.user_id then
      raise exception 'employer membership identity is admin managed';
    end if;
  end if;
  return new;
end;
$function$;

create or replace function private.protect_employer_verification_fields()
returns trigger
language plpgsql
set search_path to 'pg_catalog','public','private'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_admin boolean := false;
  v_server boolean := current_user in ('service_role','postgres');
begin
  if v_uid is not null then v_admin := private.is_admin_user(); end if;
  if not v_admin and not v_server and v_uid is not null and new.owner_id is distinct from old.owner_id then
    raise exception 'employer owner is admin managed';
  end if;
  if not v_admin and not v_server and v_uid is not null and (
    new.verified is distinct from old.verified or
    new.verification_status is distinct from old.verification_status or
    new.verified_at is distinct from old.verified_at or
    new.verified_by is distinct from old.verified_by or
    new.verification_notes is distinct from old.verification_notes
  ) then raise exception 'employer verification fields are admin managed'; end if;
  if (v_admin or v_server) and (new.verified is distinct from old.verified or new.verification_status is distinct from old.verification_status) then
    new.verified_by:=coalesce(v_uid,new.verified_by);
    new.verified_at:=now();
  end if;
  new.updated_at:=now();
  return new;
end;
$function$;

create or replace function private.protect_profile_security_fields()
returns trigger
language plpgsql
set search_path to 'pg_catalog','public','private'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_is_admin boolean := false;
  v_server boolean := current_user in ('postgres','service_role');
begin
  if v_server then new.updated_at:=now(); return new; end if;
  if v_uid is not null then
    v_is_admin := private.is_admin_user();
    if new.role is distinct from old.role and (v_uid=old.id or not v_is_admin) then raise exception 'role can only be changed by an administrator'; end if;
    if new.coin_balance is distinct from old.coin_balance and (v_uid=old.id or not v_is_admin) then raise exception 'coin balance can only be changed by an administrator or trusted backend'; end if;
    if new.verified_passport_badge_count is distinct from old.verified_passport_badge_count and (v_uid=old.id or not v_is_admin) then raise exception 'verified passport badge count is system managed'; end if;
    if (new.email_verified is distinct from old.email_verified or new.phone_verified is distinct from old.phone_verified) and (v_uid=old.id or not v_is_admin) then raise exception 'verification state is system managed'; end if;
    if (new.account_status is distinct from old.account_status or new.role_selected_at is distinct from old.role_selected_at or new.deleted_at is distinct from old.deleted_at) and (v_uid=old.id or not v_is_admin) then raise exception 'account security state is system managed'; end if;
  end if;
  new.updated_at:=now();
  return new;
end
$function$;

create or replace function private.guard_mela_ai_task_state_updates()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $function$
declare
  uid uuid := auth.uid();
  is_admin boolean := false;
begin
  if uid is null then return new; end if;
  is_admin := private.is_admin_user();
  if is_admin then return new; end if;

  if old.created_by <> uid then
    raise exception 'Only the task creator or an administrator may update an AI task';
  end if;

  if new.created_by is distinct from old.created_by
     or new.assigned_agent_id is distinct from old.assigned_agent_id
     or new.assigned_user_id is distinct from old.assigned_user_id
     or new.approval_level is distinct from old.approval_level
     or new.approval_status is distinct from old.approval_status
     or new.status is distinct from old.status
     or new.result is distinct from old.result
     or new.error_message is distinct from old.error_message
     or new.started_at is distinct from old.started_at
     or new.completed_at is distinct from old.completed_at
     or new.retry_count is distinct from old.retry_count
     or new.max_retries is distinct from old.max_retries
     or new.verification_status is distinct from old.verification_status
     or new.verification_notes is distinct from old.verification_notes then
    raise exception 'AI task execution state is managed by the platform';
  end if;

  return new;
end;
$function$;

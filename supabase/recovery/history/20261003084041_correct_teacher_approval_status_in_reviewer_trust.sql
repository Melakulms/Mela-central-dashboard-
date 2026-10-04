-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261003084041
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
    join public.teacher_profiles t on t.user_id=e.user_id and t.verification_status='approved'
    join public.mela_learning_programs lp on lp.program_key=p_program_key
    where e.user_id=p_uid and e.verified and e.active
      and (
        lp.subject_key=any(coalesce(e.subject_areas,'{}'::text[]))
        or lp.subject_title=any(coalesce(e.subject_areas,'{}'::text[]))
      )
      and (
        lp.subject_key=any(coalesce(t.subjects_taught,'{}'::text[]))
        or lp.subject_title=any(coalesce(t.subjects_taught,'{}'::text[]))
      )
  );
$function$;

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
  if private.is_admin_user() then return true; end if;
  return exists(
    select 1
    from public.educator_profiles e
    join public.teacher_profiles t on t.user_id=e.user_id and t.verification_status='approved'
    join public.mela_learning_programs lp on (
      lp.subject_key=any(coalesce(e.subject_areas,'{}'::text[]))
      or lp.subject_title=any(coalesce(e.subject_areas,'{}'::text[]))
    )
    where e.user_id=v_uid and e.verified and e.active
      and (
        lp.subject_key=any(coalesce(t.subjects_taught,'{}'::text[]))
        or lp.subject_title=any(coalesce(t.subjects_taught,'{}'::text[]))
      )
  );
end;
$function$;

create or replace function private.activate_my_educator_profile(
  p_partner_org_id uuid,
  p_role_title text default 'Educator'::text,
  p_subject_areas text[] default '{}'::text[],
  p_stage_keys text[] default '{}'::text[]
)
returns public.educator_profiles
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_org public.sector_partner_organizations%rowtype;
  v_row public.educator_profiles%rowtype;
  v_profile public.profiles%rowtype;
  v_teacher public.teacher_profiles%rowtype;
  v_subject text;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_profile from public.profiles where id=v_uid;
  if not found or v_profile.account_status <> 'active' or not (v_profile.email_verified or v_profile.phone_verified) then
    raise exception 'verified active account required';
  end if;
  if v_profile.role <> 'teacher'::public.user_role then raise exception 'teacher account required'; end if;

  select * into v_teacher from public.teacher_profiles where user_id=v_uid and verification_status='approved';
  if not found then raise exception 'approved teacher profile required'; end if;
  if coalesce(cardinality(p_subject_areas),0)=0 then raise exception 'at least one approved teaching subject is required'; end if;
  foreach v_subject in array p_subject_areas loop
    if not (
      v_subject=any(coalesce(v_teacher.subjects_taught,'{}'::text[]))
      or exists(
        select 1 from public.mela_learning_programs lp
        where (lp.subject_key=v_subject or lp.subject_title=v_subject)
          and (lp.subject_key=any(coalesce(v_teacher.subjects_taught,'{}'::text[])) or lp.subject_title=any(coalesce(v_teacher.subjects_taught,'{}'::text[])))
      )
    ) then
      raise exception 'requested review subject is not part of the approved teacher profile';
    end if;
  end loop;

  select * into v_org from public.sector_partner_organizations
  where id=p_partner_org_id and verification_status='verified';
  if not found or v_org.partner_type_key not in ('school','college_tvet','university','training_mentor') then
    raise exception 'verified education or training partner required';
  end if;
  if not private.has_sector_partner_membership(v_org.id,v_uid,false) then
    raise exception 'active partner membership required';
  end if;

  insert into public.educator_profiles(user_id,partner_organization_id,role_title,subject_areas,stage_keys,verified,verified_by,verified_at,active,updated_at)
  values(v_uid,v_org.id,coalesce(nullif(trim(p_role_title),''),'Educator'),coalesce(p_subject_areas,'{}'),coalesce(p_stage_keys,'{}'),true,v_teacher.verified_by,coalesce(v_teacher.verified_at,now()),true,now())
  on conflict(user_id) do update set
    partner_organization_id=excluded.partner_organization_id,
    role_title=excluded.role_title,
    subject_areas=excluded.subject_areas,
    stage_keys=excluded.stage_keys,
    verified=true,
    verified_by=excluded.verified_by,
    verified_at=excluded.verified_at,
    active=true,
    updated_at=now()
  returning * into v_row;
  return v_row;
end;
$function$;

create or replace function private.guard_role_specific_profile_fields()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare r text;
begin
  if private.is_admin_user() then return new; end if;
  select role::text into r from public.profiles where id=auth.uid();
  if r is null then raise exception 'profile role could not be verified'; end if;
  if TG_TABLE_NAME='student_profiles' and r <> 'student' then raise exception 'only student accounts may modify student profiles'; end if;
  if TG_TABLE_NAME='teacher_profiles' and r <> 'teacher' then raise exception 'only teacher accounts may modify teacher profiles'; end if;
  if TG_TABLE_NAME='parent_profiles' and r <> 'parent' then raise exception 'only parent accounts may modify parent profiles'; end if;
  if TG_TABLE_NAME='company_profiles' and r <> 'company' then raise exception 'only company accounts may modify company profiles'; end if;
  if TG_TABLE_NAME='teacher_profiles' then
    if new.verification_status is distinct from old.verification_status or new.verified_by is distinct from old.verified_by or new.verified_at is distinct from old.verified_at or new.content_creator_status is distinct from old.content_creator_status then
      raise exception 'protected teacher verification fields require authorized system operation';
    end if;
    if old.verification_status='approved' and (
      new.qualification is distinct from old.qualification
      or new.subjects_taught is distinct from old.subjects_taught
      or new.grade_levels is distinct from old.grade_levels
      or new.teaching_experience_years is distinct from old.teaching_experience_years
      or new.institution is distinct from old.institution
      or new.certifications is distinct from old.certifications
    ) then
      raise exception 'approved teacher qualification fields require authorized admin review';
    end if;
  end if;
  if TG_TABLE_NAME='company_profiles' and (new.verification_status is distinct from old.verification_status or new.verified_by is distinct from old.verified_by or new.verified_at is distinct from old.verified_at or new.employer_id is distinct from old.employer_id) then
    raise exception 'protected company verification/ownership fields require authorized system operation';
  end if;
  if new.user_id is distinct from old.user_id then raise exception 'profile ownership cannot be changed'; end if;
  return new;
end;
$function$;

;

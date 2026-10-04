-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260816233410
create or replace function private.set_my_education_stage_v36(p_stage_key text,p_grade_level integer default null,p_institution_name text default null)
returns public.profiles
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_profile public.profiles%rowtype;
  v_stage public.education_audience_stages%rowtype;
  v_grade smallint;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if not private.current_account_can_access() then raise exception 'verified active account required'; end if;

  select * into v_profile from public.profiles where id=v_uid for update;
  if not found then raise exception 'profile not found'; end if;
  if v_profile.role <> 'student'::public.user_role or v_profile.role_selected_at is null then
    raise exception 'student account type required';
  end if;

  select * into v_stage from public.education_audience_stages where stage_key=p_stage_key;
  if not found then raise exception 'unsupported education stage'; end if;

  if v_profile.education_stage_key is not null and v_profile.education_stage_key <> p_stage_key then
    raise exception 'education stage is locked; administrator review required';
  end if;

  if v_stage.school_stage then
    if p_grade_level is null or p_grade_level < v_stage.min_grade or p_grade_level > v_stage.max_grade then
      raise exception 'grade level must be between % and % for this stage',v_stage.min_grade,v_stage.max_grade;
    end if;
    v_grade:=p_grade_level::smallint;
  else
    v_grade:=null;
  end if;

  update public.profiles
     set education_stage_key=p_stage_key,
         grade_level=v_grade,
         institution_name=coalesce(nullif(btrim(p_institution_name),''),institution_name),
         onboarding_step=case when onboarding_step in ('account_type','profile') then 'profile' else onboarding_step end,
         updated_at=now()
   where id=v_uid
   returning * into v_profile;

  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
  values(v_uid,'set_education_stage','profile',v_uid,jsonb_build_object('stage_key',p_stage_key,'grade_level',v_grade));

  return v_profile;
end;
$$;
revoke all on function private.set_my_education_stage_v36(text,integer,text) from public,anon,authenticated;

create or replace function public.set_my_education_stage_v36(p_stage_key text,p_grade_level integer default null,p_institution_name text default null)
returns public.profiles
language sql
set search_path=''
as $$ select * from private.set_my_education_stage_v36(p_stage_key,p_grade_level,p_institution_name); $$;
revoke all on function public.set_my_education_stage_v36(text,integer,text) from public,anon;
grant execute on function public.set_my_education_stage_v36(text,integer,text) to authenticated,service_role;
;

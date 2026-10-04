-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002190817
create or replace function private.get_guardian_learner_progress(p_learner_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_profile jsonb;
  v_courses jsonb;
  v_practice jsonb;
  v_badges integer;
  v_skills integer;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if not private.has_verified_guardian_link(v_uid, p_learner_id) and not private.is_admin_user() then
    raise exception 'verified guardian relationship required';
  end if;

  select jsonb_build_object(
    'id', p.id,
    'full_name', p.full_name,
    'education_stage_key', p.education_stage_key,
    'grade_level', p.grade_level,
    'institution_name', p.institution_name
  ) into v_profile
  from public.profiles p
  where p.id=p_learner_id and p.deleted_at is null;

  if v_profile is null then raise exception 'learner not found'; end if;

  select jsonb_build_object(
    'enrolled', count(*),
    'completed', count(*) filter (where ce.completed_at is not null),
    'average_progress_pct', coalesce(round(avg(ce.progress_pct)::numeric,1),0)
  ) into v_courses
  from public.course_enrollments ce
  where ce.user_id=p_learner_id;

  select jsonb_build_object(
    'completed_sessions', count(*) filter (where ps.status='completed'),
    'average_score_percent', coalesce(round(avg(ps.score_percent) filter (where ps.status='completed' and ps.score_percent is not null),1),0),
    'latest_completed_at', max(ps.completed_at) filter (where ps.status='completed')
  ) into v_practice
  from public.practice_sessions ps
  where ps.user_id=p_learner_id;

  select count(*) into v_badges from public.user_badges ub where ub.user_id=p_learner_id;
  select count(*) into v_skills from public.verified_skills vs where vs.user_id=p_learner_id and coalesce(vs.verified,false);

  return jsonb_build_object(
    'learner', v_profile,
    'courses', v_courses,
    'practice', v_practice,
    'badge_count', v_badges,
    'verified_skill_count', v_skills
  );
end;
$function$;

create or replace function public.get_my_guardian_learner_progress(p_learner_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $function$
  select private.get_guardian_learner_progress(p_learner_id);
$function$;

revoke all on function public.get_my_guardian_learner_progress(uuid) from public;
grant execute on function public.get_my_guardian_learner_progress(uuid) to authenticated;
;

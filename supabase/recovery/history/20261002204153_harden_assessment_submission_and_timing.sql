-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002204153
create or replace function public.guard_assessment_attempt_mutation()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if tg_op='UPDATE' and not private.is_admin_user() then
    if new.id is distinct from old.id
       or new.assessment_id is distinct from old.assessment_id
       or new.user_id is distinct from old.user_id
       or new.attempt_no is distinct from old.attempt_no
       or new.started_at is distinct from old.started_at
       or new.proctored is distinct from old.proctored
       or new.language_code is distinct from old.language_code then
      raise exception 'Assessment attempt identity/configuration is immutable';
    end if;
  end if;
  return new;
end;
$function$;

create or replace function private.guard_assessment_attempt_scoring_fields()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if private.is_admin_user() or pg_catalog.pg_trigger_depth() > 1 then
    return new;
  end if;

  if new.id is distinct from old.id
     or new.assessment_id is distinct from old.assessment_id
     or new.user_id is distinct from old.user_id
     or new.attempt_no is distinct from old.attempt_no
     or new.started_at is distinct from old.started_at
     or new.duration_seconds is distinct from old.duration_seconds
     or new.score is distinct from old.score
     or new.passed is distinct from old.passed
     or new.integrity_score is distinct from old.integrity_score
     or new.proctored is distinct from old.proctored
     or new.proctor_status is distinct from old.proctor_status
     or new.reviewed_at is distinct from old.reviewed_at
     or new.reviewed_by is distinct from old.reviewed_by
     or new.review_notes is distinct from old.review_notes then
    raise exception 'protected assessment attempt fields can only be changed by the assessment system or administrators';
  end if;
  return new;
end;
$function$;

create or replace function private.grade_assessment_attempt()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $function$
declare
  v_total numeric;
  v_earned numeric;
  v_score numeric;
  v_pass_score integer;
  v_passed boolean;
  v_has_clear_proctor boolean;
  v_expected integer;
  v_answered integer;
  v_duration_minutes integer;
  v_duration_seconds integer;
begin
  if old.status = 'in_progress' and new.status = 'submitted' then
    select sa.pass_score, sa.duration_minutes
      into v_pass_score, v_duration_minutes
    from public.skill_assessments sa
    where sa.id = new.assessment_id;

    if not found then
      raise exception 'Assessment configuration not found';
    end if;

    select count(*)::integer
      into v_expected
    from public.assessment_attempt_questions aq
    where aq.attempt_id = new.id;

    select count(*)::integer
      into v_answered
    from public.assessment_responses r
    join public.assessment_attempt_questions aq
      on aq.attempt_id = r.attempt_id and aq.question_id = r.question_id
    where r.attempt_id = new.id
      and r.response is not null
      and r.response is distinct from 'null'::jsonb
      and not (jsonb_typeof(r.response) = 'string' and btrim(r.response #>> '{}') = '');

    if v_expected <= 0 then
      raise exception 'Attempt has no questions to grade';
    end if;
    if v_answered <> v_expected then
      raise exception 'Answer every question before submitting';
    end if;

    v_duration_seconds := greatest(0, floor(extract(epoch from (clock_timestamp() - new.started_at)))::integer);

    if v_duration_seconds > (v_duration_minutes * 60 + 30) then
      update public.assessment_attempts
      set submitted_at = clock_timestamp(),
          duration_seconds = v_duration_seconds,
          status = 'void',
          score = null,
          passed = false,
          metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object('void_reason','time_limit_exceeded','duration_limit_seconds',v_duration_minutes*60)
      where id = new.id;
      return new;
    end if;

    select coalesce(sum(aq.points_snapshot),0),
           coalesce(sum(case when r.response = k.correct_answer then aq.points_snapshot else 0 end),0)
      into v_total, v_earned
    from public.assessment_attempt_questions aq
    left join public.assessment_responses r
      on r.attempt_id = aq.attempt_id and r.question_id = aq.question_id
    left join private.assessment_answer_keys k on k.question_id = aq.question_id
    where aq.attempt_id = new.id;

    if v_total <= 0 then
      raise exception 'Attempt has no questions to grade';
    end if;

    v_score := round((v_earned / v_total) * 100, 2);
    v_passed := v_score >= v_pass_score;

    select exists (
      select 1 from public.proctor_audit_logs l
      where l.attempt_id = new.id
        and l.event_type = 'session_summary'
        and coalesce(l.flagged,false) = false
        and coalesce(l.face_detection_confidence,1) >= 0.70
        and coalesce(l.tab_switch_count,0) <= 3
    ) into v_has_clear_proctor;

    update public.assessment_attempts
    set submitted_at = clock_timestamp(),
        duration_seconds = v_duration_seconds,
        score = v_score,
        passed = v_passed,
        proctor_status = case
          when not new.proctored then 'not_required'
          when v_has_clear_proctor then 'clear'
          else 'pending'
        end,
        status = case
          when not new.proctored then 'graded'
          when v_has_clear_proctor then 'graded'
          else 'review_required'
        end,
        reviewed_at = case when (not new.proctored or v_has_clear_proctor) then clock_timestamp() else null end
    where id = new.id;

    perform private.issue_assessment_verified_skill(new.id);
  end if;
  return new;
end;
$function$;

create or replace function public.submit_my_assessment_attempt(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_attempt public.assessment_attempts%rowtype;
  v_expected integer;
  v_answered integer;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  select * into v_attempt
  from public.assessment_attempts
  where id = p_attempt_id
  for update;

  if not found or v_attempt.user_id is distinct from v_uid then
    raise exception 'assessment attempt not found';
  end if;
  if v_attempt.status <> 'in_progress' then
    raise exception 'assessment attempt is not in progress';
  end if;

  select count(*)::integer into v_expected
  from public.assessment_attempt_questions
  where attempt_id = p_attempt_id;

  select count(*)::integer into v_answered
  from public.assessment_responses r
  join public.assessment_attempt_questions aq
    on aq.attempt_id = r.attempt_id and aq.question_id = r.question_id
  where r.attempt_id = p_attempt_id
    and r.response is not null
    and r.response is distinct from 'null'::jsonb
    and not (jsonb_typeof(r.response) = 'string' and btrim(r.response #>> '{}') = '');

  if v_expected <= 0 then
    raise exception 'attempt has no questions';
  end if;
  if v_answered <> v_expected then
    raise exception 'Answer every question before submitting';
  end if;

  update public.assessment_attempts
  set status = 'submitted'
  where id = p_attempt_id and status = 'in_progress';

  select * into v_attempt
  from public.assessment_attempts
  where id = p_attempt_id;

  return jsonb_build_object(
    'id', v_attempt.id,
    'status', v_attempt.status,
    'score', v_attempt.score,
    'passed', v_attempt.passed,
    'proctor_status', v_attempt.proctor_status,
    'duration_seconds', v_attempt.duration_seconds,
    'submitted_at', v_attempt.submitted_at
  );
end;
$function$;

revoke all on function public.submit_my_assessment_attempt(uuid) from public, anon;
grant execute on function public.submit_my_assessment_attempt(uuid) to authenticated, service_role;
;

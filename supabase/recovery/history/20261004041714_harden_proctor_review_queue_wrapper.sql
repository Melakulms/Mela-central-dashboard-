-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261004041714
create or replace function private.get_proctor_review_queue(p_limit integer default 50)
returns table(
  id uuid,
  assessment_id uuid,
  assessment_title text,
  learner_id uuid,
  attempt_no integer,
  started_at timestamptz,
  submitted_at timestamptz,
  duration_seconds integer,
  score numeric,
  passed boolean,
  integrity_score numeric,
  proctor_status text,
  status text,
  event_count bigint,
  tab_hidden_count bigint,
  window_blur_count bigint,
  camera_permission_count bigint,
  network_change_count bigint
)
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin_user() then
    raise exception 'admin authorization with MFA required' using errcode='42501';
  end if;

  return query
  select a.id,a.assessment_id,sa.title,a.user_id,a.attempt_no,a.started_at,a.submitted_at,a.duration_seconds,
         a.score,a.passed,a.integrity_score,a.proctor_status,a.status,
         count(l.id)::bigint,
         count(*) filter(where l.event_type='tab_hidden')::bigint,
         count(*) filter(where l.event_type='window_blur')::bigint,
         count(*) filter(where l.event_type='camera_permission')::bigint,
         count(*) filter(where l.event_type='network_change')::bigint
  from public.assessment_attempts a
  join public.skill_assessments sa on sa.id=a.assessment_id
  left join public.proctor_audit_logs l on l.attempt_id=a.id
  where a.proctored=true and a.status='review_required' and a.proctor_status='pending'
  group by a.id,a.assessment_id,sa.title,a.user_id,a.attempt_no,a.started_at,a.submitted_at,a.duration_seconds,
           a.score,a.passed,a.integrity_score,a.proctor_status,a.status
  order by a.submitted_at nulls last,a.started_at
  limit least(greatest(coalesce(p_limit,50),1),200);
end;
$function$;

create or replace function public.get_proctor_review_queue(p_limit integer default 50)
returns table(
  id uuid,
  assessment_id uuid,
  assessment_title text,
  learner_id uuid,
  attempt_no integer,
  started_at timestamptz,
  submitted_at timestamptz,
  duration_seconds integer,
  score numeric,
  passed boolean,
  integrity_score numeric,
  proctor_status text,
  status text,
  event_count bigint,
  tab_hidden_count bigint,
  window_blur_count bigint,
  camera_permission_count bigint,
  network_change_count bigint
)
language sql
security invoker
set search_path to ''
as $function$
  select * from private.get_proctor_review_queue(p_limit);
$function$;

revoke all on function private.get_proctor_review_queue(integer) from public, anon;
grant execute on function private.get_proctor_review_queue(integer) to authenticated, service_role;
revoke all on function public.get_proctor_review_queue(integer) from public, anon;
grant execute on function public.get_proctor_review_queue(integer) to authenticated, service_role;
;

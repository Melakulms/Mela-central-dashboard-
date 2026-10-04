-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815201316
create or replace function private.get_question_quality_progress_v21()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_allowed boolean;
  v_summary jsonb;
  v_programs jsonb;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  v_allowed := private.can_review_questions_v18();
  if not v_allowed then raise exception 'verified educator or admin access required'; end if;

  select jsonb_build_object(
    'active_questions', count(*) filter(where q.active),
    'mastery_ready', count(*) filter(where q.active and q.validation_status in ('deterministic_validated','educator_verified')),
    'educator_verified', count(*) filter(where q.active and q.validation_status='educator_verified'),
    'review_required', count(*) filter(where q.active and q.validation_status='review_required'),
    'replacement_candidates', (select count(*) from private.mela_question_generation_candidates_v18),
    'replacement_queued', (select count(*) from private.mela_question_replacement_targets_v18 where status='queued'),
    'replacement_generated', (select count(*) from private.mela_question_replacement_targets_v18 where status in ('generated','machine_validated','educator_approved')),
    'replacement_promoted', (select count(*) from private.mela_question_replacement_targets_v18 where status='promoted'),
    'review_slices_total', (select count(*) from private.mela_question_review_slices_v18),
    'review_slices_complete', (select count(*) from private.mela_question_review_slices_v18 where status='approved'),
    'review_slices_in_review', (select count(*) from private.mela_question_review_slices_v18 where status in ('in_review','changes_required'))
  ) into v_summary
  from public.mela_question_bank q;

  select coalesce(jsonb_agg(jsonb_build_object(
    'program_key',r.program_key,
    'grade_level',r.grade_level,
    'subject_title',r.subject_title,
    'track_key',r.track_key,
    'current_mastery_count',r.current_mastery_count,
    'target_mastery_count',r.target_mastery_count,
    'questions_needed',r.questions_needed,
    'status',r.status
  ) order by r.questions_needed desc,r.grade_level,r.subject_title),'[]'::jsonb)
  into v_programs
  from private.mela_question_regeneration_queue_v18 r
  where private.question_reviewer_allowed_v18(v_uid,r.program_key);

  return jsonb_build_object('summary',v_summary,'programs',v_programs,'generated_at',now());
end $$;

revoke all on function private.get_question_quality_progress_v21() from public,anon,authenticated;
grant execute on function private.get_question_quality_progress_v21() to service_role;

create or replace function public.get_question_quality_progress_v21()
returns jsonb
language sql
stable
security invoker
set search_path=''
as $$ select private.get_question_quality_progress_v21(); $$;

revoke all on function public.get_question_quality_progress_v21() from public,anon;
grant execute on function public.get_question_quality_progress_v21() to authenticated,service_role;
;

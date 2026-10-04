-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815205303
create or replace function public.get_mela_operational_health_v18()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_base jsonb;
  v_mastery bigint;
  v_review_required bigint;
  v_educator bigint;
  v_rebuild_needed bigint;
  v_programs_below bigint;
  v_optional_needed bigint;
  v_optional_programs bigint;
  v_core_at_target bigint;
begin
  v_base := public.get_mela_operational_health_v17();
  select count(*) into v_mastery from public.mela_question_bank where active and validation_status in ('deterministic_validated','educator_verified');
  select count(*) into v_review_required from public.mela_question_bank where active and validation_status='review_required';
  select count(*) into v_educator from public.mela_question_bank where active and validation_status='educator_verified';

  select coalesce(sum(r.questions_needed),0),count(*) filter(where r.current_mastery_count<r.target_mastery_count),count(*) filter(where r.current_mastery_count>=r.target_mastery_count)
    into v_rebuild_needed,v_programs_below,v_core_at_target
  from private.mela_question_regeneration_queue_v18 r
  join public.mela_learning_programs p on p.program_key=r.program_key
  where p.subject_title<>'Foreign Language';

  select coalesce(sum(r.questions_needed),0),count(*) filter(where r.current_mastery_count<r.target_mastery_count)
    into v_optional_needed,v_optional_programs
  from private.mela_question_regeneration_queue_v18 r
  join public.mela_learning_programs p on p.program_key=r.program_key
  where p.subject_title='Foreign Language';

  return v_base || jsonb_build_object(
    'question_quality_ready',v_rebuild_needed=0 and v_programs_below=0 and v_educator>=62000,
    'mastery_candidates',v_mastery,
    'supplemental_review_required',v_review_required,
    'educator_verified_questions',v_educator,
    'mastery_questions_needed_for_500',v_rebuild_needed,
    'programs_below_500_mastery',v_programs_below,
    'core_programs_at_or_above_500',v_core_at_target,
    'optional_foreign_language_questions_needed',v_optional_needed,
    'optional_foreign_language_programs_pending',v_optional_programs,
    'question_quality_audit_version','v30'
  );
end $$;

revoke all on function public.get_mela_operational_health_v18() from public,anon,authenticated;
grant execute on function public.get_mela_operational_health_v18() to service_role;
;

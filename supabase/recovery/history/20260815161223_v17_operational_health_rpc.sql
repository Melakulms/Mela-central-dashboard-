-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815161223
create or replace function public.get_mela_operational_health_v17()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_active_questions bigint;
  v_questions_without_grading bigint;
  v_programs_not_800 bigint;
  v_chapters_without_materials bigint;
  v_sale_enabled bigint;
  v_rls_missing bigint;
  v_public_secdef bigint;
  v_pending_required bigint;
  v_blocked_required bigint;
  v_work_domains bigint;
  v_edu_domains bigint;
begin
  select count(*) into v_active_questions from public.mela_question_bank where active;
  select count(*) into v_questions_without_grading
    from public.mela_question_bank q
    left join private.mela_question_grading_v12 g on g.question_id=q.id
    where q.active and g.question_id is null;
  select count(*) into v_programs_not_800 from (
    select p.program_key
    from public.mela_learning_programs p
    left join public.mela_question_bank q on q.program_key=p.program_key and q.active
    where p.program_kind='school_subject' and p.grade_level between 1 and 12
    group by p.program_key having count(q.*)<>800
  ) x;
  select count(*) into v_chapters_without_materials
    from public.mela_learning_chapters c
    where c.status='published' and not exists(
      select 1 from public.mela_learning_chapter_materials m where m.chapter_id=c.id and m.status='published'
    );
  select count(*) into v_sale_enabled from public.mela_learning_products where sale_enabled;
  select count(*) into v_rls_missing
    from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and not c.relrowsecurity;
  select count(*) into v_public_secdef
    from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef and has_function_privilege('public',p.oid,'EXECUTE');
  select count(*) into v_pending_required from public.platform_launch_requirements where required and manual_status='pending';
  select count(*) into v_blocked_required from public.platform_launch_requirements where required and manual_status='blocked';
  select count(distinct canonical_domain) into v_work_domains from public.global_opportunity_sources where active and verification_status='verified' and source_category='work_employer';
  select count(distinct canonical_domain) into v_edu_domains from public.global_opportunity_sources where active and verification_status='verified' and source_category='scholarship_institution';
  return jsonb_build_object(
    'data_integrity_ok', v_active_questions=100800 and v_questions_without_grading=0 and v_programs_not_800=0 and v_chapters_without_materials=0 and v_sale_enabled=0 and v_rls_missing=0 and v_public_secdef=0,
    'launch_ready', v_pending_required=0 and v_blocked_required=0,
    'active_questions',v_active_questions,
    'questions_without_grading',v_questions_without_grading,
    'school_programs_not_800',v_programs_not_800,
    'chapters_without_materials',v_chapters_without_materials,
    'sale_enabled_products',v_sale_enabled,
    'public_tables_without_rls',v_rls_missing,
    'public_secdef_public_exec',v_public_secdef,
    'required_pending',v_pending_required,
    'required_blocked',v_blocked_required,
    'verified_work_domains',v_work_domains,
    'verified_education_domains',v_edu_domains,
    'checked_at',now()
  );
end;
$$;
revoke all on function public.get_mela_operational_health_v17() from public, anon, authenticated;
grant execute on function public.get_mela_operational_health_v17() to service_role;
;

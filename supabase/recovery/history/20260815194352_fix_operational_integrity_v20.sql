-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815194352
create or replace function public.get_mela_operational_health_v17()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_active_questions bigint;
  v_grading_rows bigint;
  v_published_chapters bigint;
  v_published_materials bigint;
  v_sale_enabled bigint;
  v_rls_missing bigint;
  v_public_secdef bigint;
  v_pending_required bigint;
  v_blocked_required bigint;
  v_work_domains bigint;
  v_edu_domains bigint;
  v_deep jsonb;
  v_deep_at timestamptz;
  v_deep_ok boolean := false;
begin
  select count(*) into v_active_questions from public.mela_question_bank where active;
  select count(*) into v_grading_rows from private.mela_question_grading_v12;
  select count(*) into v_published_chapters from public.mela_learning_chapters where status='published';
  select count(*) into v_published_materials from public.mela_learning_chapter_materials where status='published';
  select count(*) into v_sale_enabled from public.mela_learning_products where sale_enabled;
  select count(*) into v_rls_missing from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity;
  select count(*) into v_public_secdef from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and has_function_privilege('public',p.oid,'EXECUTE');
  select count(*) into v_pending_required from public.platform_launch_requirements where required and manual_status='pending';
  select count(*) into v_blocked_required from public.platform_launch_requirements where required and manual_status='blocked';
  select count(distinct canonical_domain) into v_work_domains from public.global_opportunity_sources where active and verification_status='verified' and source_category='work_employer';
  select count(distinct canonical_domain) into v_edu_domains from public.global_opportunity_sources where active and verification_status='verified' and source_category='scholarship_institution';
  select payload, measured_at into v_deep, v_deep_at from private.mela_release_evidence where evidence_kind='backup_manifest' and status='pass' order by measured_at desc limit 1;
  v_deep_ok := coalesce((v_deep->'invariants'->>'questions_without_grading')::int,0)=0 and coalesce((v_deep->'invariants'->>'chapters_without_materials')::int,0)=0;
  return jsonb_build_object(
    'data_integrity_ok',v_active_questions=v_grading_rows and v_active_questions>=100000 and v_published_chapters>=887 and v_published_materials>=10384 and v_sale_enabled=0 and v_rls_missing=0 and v_public_secdef=0 and v_deep_ok,
    'launch_ready',v_pending_required=0 and v_blocked_required=0,
    'active_questions',v_active_questions,'grading_rows',v_grading_rows,'published_chapters',v_published_chapters,'published_materials',v_published_materials,'sale_enabled_products',v_sale_enabled,'public_tables_without_rls',v_rls_missing,'public_secdef_public_exec',v_public_secdef,'required_pending',v_pending_required,'required_blocked',v_blocked_required,'verified_work_domains',v_work_domains,'verified_education_domains',v_edu_domains,'deep_audit_ok',v_deep_ok,'deep_audit_at',v_deep_at,'checked_at',now());
end;
$$;
;

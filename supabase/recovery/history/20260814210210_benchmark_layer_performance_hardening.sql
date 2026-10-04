-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814210210
create index if not exists learner_offline_sync_state_pack_idx on public.learner_offline_sync_state(pack_id);
create index if not exists mela_offline_content_packs_language_idx on public.mela_offline_content_packs(language_code);

drop policy if exists education_benchmark_practices_admin_write on public.education_benchmark_practices;
create policy education_benchmark_practices_admin_insert on public.education_benchmark_practices for insert to authenticated with check (private.is_admin_user());
create policy education_benchmark_practices_admin_update on public.education_benchmark_practices for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy education_benchmark_practices_admin_delete on public.education_benchmark_practices for delete to authenticated using (private.is_admin_user());

drop policy if exists mela_outcome_metrics_admin_write on public.mela_outcome_metrics;
create policy mela_outcome_metrics_admin_insert on public.mela_outcome_metrics for insert to authenticated with check (private.is_admin_user());
create policy mela_outcome_metrics_admin_update on public.mela_outcome_metrics for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy mela_outcome_metrics_admin_delete on public.mela_outcome_metrics for delete to authenticated using (private.is_admin_user());

drop policy if exists mela_offline_content_packs_admin_write on public.mela_offline_content_packs;
create policy mela_offline_content_packs_admin_insert on public.mela_offline_content_packs for insert to authenticated with check (private.is_admin_user());
create policy mela_offline_content_packs_admin_update on public.mela_offline_content_packs for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy mela_offline_content_packs_admin_delete on public.mela_offline_content_packs for delete to authenticated using (private.is_admin_user());
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815105338
create index if not exists content_accessibility_metadata_reviewed_by_idx on public.content_accessibility_metadata(reviewed_by) where reviewed_by is not null;
create index if not exists external_application_events_user_id_idx on public.external_application_events(user_id);
create index if not exists external_application_tracking_opportunity_id_idx on public.external_application_tracking(opportunity_id) where opportunity_id is not null;

drop policy if exists accessibility_metadata_admin_write on public.content_accessibility_metadata;
drop policy if exists accessibility_metadata_read on public.content_accessibility_metadata;
create policy accessibility_metadata_read on public.content_accessibility_metadata for select to authenticated using (true);
create policy accessibility_metadata_admin_insert on public.content_accessibility_metadata for insert to authenticated with check (private.is_admin_user());
create policy accessibility_metadata_admin_update on public.content_accessibility_metadata for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy accessibility_metadata_admin_delete on public.content_accessibility_metadata for delete to authenticated using (private.is_admin_user());

drop policy if exists global_sources_admin_write on public.global_opportunity_sources;
drop policy if exists global_sources_verified_read on public.global_opportunity_sources;
create policy global_sources_read on public.global_opportunity_sources for select to authenticated using ((active and verification_status='verified') or private.is_admin_user());
create policy global_sources_admin_insert on public.global_opportunity_sources for insert to authenticated with check (private.is_admin_user());
create policy global_sources_admin_update on public.global_opportunity_sources for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy global_sources_admin_delete on public.global_opportunity_sources for delete to authenticated using (private.is_admin_user());
;

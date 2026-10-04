-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814204716
-- Consolidate duplicate educator policies while preserving the restrictive master gate.
drop policy if exists educator_classrooms_owner on public.educator_classrooms;
drop policy if exists educator_classrooms_visible on public.educator_classrooms;
create policy educator_classrooms_select on public.educator_classrooms for select to authenticated using (private.can_view_classroom(id,(select auth.uid())));
create policy educator_classrooms_write on public.educator_classrooms for insert to authenticated with check (educator_id=(select auth.uid()) or private.is_admin_user());
create policy educator_classrooms_update on public.educator_classrooms for update to authenticated using (educator_id=(select auth.uid()) or private.is_admin_user()) with check (educator_id=(select auth.uid()) or private.is_admin_user());
create policy educator_classrooms_delete on public.educator_classrooms for delete to authenticated using (educator_id=(select auth.uid()) or private.is_admin_user());

drop policy if exists educator_profiles_admin_write on public.educator_profiles;
drop policy if exists educator_profiles_self on public.educator_profiles;
drop policy if exists educator_profiles_visible on public.educator_profiles;
drop policy if exists educator_profiles_self_update on public.educator_profiles;
create policy educator_profiles_select on public.educator_profiles for select to authenticated using ((select auth.uid())=user_id or private.is_admin_user() or private.has_sector_partner_membership(partner_organization_id,(select auth.uid()),true));
create policy educator_profiles_insert on public.educator_profiles for insert to authenticated with check (private.is_admin_user());
create policy educator_profiles_update on public.educator_profiles for update to authenticated using ((select auth.uid())=user_id or private.is_admin_user()) with check ((select auth.uid())=user_id or private.is_admin_user());
create policy educator_profiles_delete on public.educator_profiles for delete to authenticated using (private.is_admin_user());

-- Cover foreign keys used by the new learning-to-opportunity system.
create index if not exists learning_competencies_stage_idx on public.learning_competencies(stage_key);
create index if not exists learner_mastery_records_comp_idx on public.learner_mastery_records(competency_id);
create index if not exists learner_mastery_evidence_comp_idx on public.learner_mastery_evidence(competency_id);
create index if not exists learner_mastery_evidence_verified_by_idx on public.learner_mastery_evidence(verified_by) where verified_by is not null;
create index if not exists learner_projects_stage_idx on public.learner_projects(stage_key);
create index if not exists learner_projects_verified_by_idx on public.learner_projects(verified_by) where verified_by is not null;
create index if not exists learner_project_competencies_comp_idx on public.learner_project_competencies(competency_id);
create index if not exists educator_profiles_partner_idx on public.educator_profiles(partner_organization_id);
create index if not exists educator_profiles_verified_by_idx on public.educator_profiles(verified_by) where verified_by is not null;
create index if not exists educator_classrooms_partner_idx on public.educator_classrooms(partner_organization_id);
create index if not exists educator_classrooms_stage_idx on public.educator_classrooms(stage_key);
create index if not exists educator_observations_classroom_idx on public.educator_observations(classroom_id);
create index if not exists educator_observations_educator_idx on public.educator_observations(educator_id,created_at desc);
create index if not exists educator_observations_comp_idx on public.educator_observations(competency_id) where competency_id is not null;
create index if not exists educator_copilot_requests_classroom_idx on public.educator_copilot_requests(classroom_id) where classroom_id is not null;
create index if not exists mela_transition_plans_path_idx on public.mela_transition_plans(career_path_id) where career_path_id is not null;
create index if not exists opportunity_graph_nodes_stage_idx on public.opportunity_graph_nodes(stage_key) where stage_key is not null;
create index if not exists opportunity_graph_nodes_path_idx on public.opportunity_graph_nodes(career_path_id) where career_path_id is not null;
;

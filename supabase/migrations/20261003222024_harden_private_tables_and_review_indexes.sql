-- Private backend data: no direct browser access for any application role.
-- SECURITY DEFINER owners and service_role retain their existing backend paths.
set lock_timeout = '5s';
do $migration$
declare t text;
begin
  foreach t in array array[
    'beta_auth_rate_limits','mela_question_answer_keys','mela_question_generation_candidates_v18',
    'mela_question_grading_v12','mela_question_quality_audit_v18','mela_question_regeneration_queue_v18',
    'mela_question_replacement_targets_v18','mela_question_review_decisions_v18','mela_question_review_slices_v18',
    'mela_release_evidence','payment_webhook_events','practice_answer_keys'
  ] loop
    execute format('alter table private.%I enable row level security',t);
    execute format('revoke all on table private.%I from public, anon, authenticated',t);
    execute format('create policy backend_service_only on private.%I for all to service_role using (true) with check (true)',t);
  end loop;
end
$migration$;
create index if not exists educator_review_authorizations_granted_by_idx on private.educator_review_authorizations(granted_by);
create index if not exists mela_chapter_review_decisions_chapter_id_idx on private.mela_chapter_review_decisions(chapter_id);
create index if not exists beta_access_invites_created_by_idx on public.beta_access_invites(created_by);
create index if not exists beta_access_invites_used_by_idx on public.beta_access_invites(used_by);

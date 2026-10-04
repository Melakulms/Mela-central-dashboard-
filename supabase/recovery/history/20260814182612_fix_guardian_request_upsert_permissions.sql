-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814182612
create policy guardian_relationships_update_owner_pending on public.guardian_relationships for update to authenticated using (learner_id=(select auth.uid()) and status='pending') with check (learner_id=(select auth.uid()) and status='pending'); grant update on public.guardian_relationships to authenticated;
;

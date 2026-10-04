-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821220207
drop policy if exists guardian_relationships_insert on public.guardian_relationships;
create policy guardian_relationships_insert on public.guardian_relationships
for insert to authenticated
with check (
  learner_id = (select auth.uid())
  and status = 'pending'
  and verified_at is null
  and verified_by is null
  and (guardian_user_id is null or guardian_user_id <> (select auth.uid()))
);
;

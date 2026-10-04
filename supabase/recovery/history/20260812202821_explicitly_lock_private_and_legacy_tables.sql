-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812202821
create policy "Service role answer key access" on private.assessment_answer_keys
for all to service_role using (true) with check (true);

create policy "Legacy Mela table blocked from clients" on public."Mela"
for all to anon, authenticated using (false) with check (false);
;

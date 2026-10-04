-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812214836
create index if not exists employers_verified_by_idx on public.employers(verified_by);
;

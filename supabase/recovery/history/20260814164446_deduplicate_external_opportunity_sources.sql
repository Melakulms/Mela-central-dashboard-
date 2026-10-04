-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814164446
create unique index if not exists opportunities_external_source_url_unique_idx on public.opportunities(source_url) where employer_id is null and source_url is not null;
;

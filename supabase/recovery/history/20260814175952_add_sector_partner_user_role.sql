-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814175952
alter type public.user_role add value if not exists 'partner';
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260809154920
alter type public.app_language add value if not exists 'ti';
alter type public.app_language add value if not exists 'so';
;

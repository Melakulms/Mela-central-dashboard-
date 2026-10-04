-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260816062452
alter type public.user_role add value if not exists 'parent';
alter type public.user_role add value if not exists 'teacher';
alter type public.user_role add value if not exists 'company';
;

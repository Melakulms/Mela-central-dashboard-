-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822043034
revoke select on table public.platform_feature_flags from anon, authenticated;
grant select (feature_key, label, description, enabled, maintenance_message) on table public.platform_feature_flags to anon, authenticated;
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813082935
create index if not exists platform_feature_flags_updated_by_idx on public.platform_feature_flags(updated_by) where updated_by is not null;
create index if not exists platform_announcements_created_by_idx on public.platform_announcements(created_by) where created_by is not null;
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260816231907
create index if not exists company_profiles_verified_by_idx on public.company_profiles(verified_by);
create index if not exists opportunities_reviewed_by_idx on public.opportunities(reviewed_by);
create index if not exists parent_link_invites_redeemed_by_idx on public.parent_link_invites(redeemed_by);
create index if not exists teacher_profiles_verified_by_idx on public.teacher_profiles(verified_by);
create index if not exists user_subscriptions_plan_id_idx on public.user_subscriptions(plan_id);
;

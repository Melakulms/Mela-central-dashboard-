-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814182757
create index if not exists guardian_relationships_guardian_user_idx on public.guardian_relationships(guardian_user_id) where guardian_user_id is not null;
create index if not exists guardian_relationships_verified_by_idx on public.guardian_relationships(verified_by) where verified_by is not null;
create index if not exists platform_audience_subsections_section_idx on public.platform_audience_subsections(section_key);
create index if not exists sector_partner_members_user_idx on public.sector_partner_members(user_id);
create index if not exists sector_partner_organizations_owner_idx on public.sector_partner_organizations(owner_id);
create index if not exists sector_partner_organizations_verified_by_idx on public.sector_partner_organizations(verified_by) where verified_by is not null;
create index if not exists sector_partner_registration_type_idx on public.sector_partner_registration_requests(partner_type_key);
create index if not exists sector_partner_registration_reviewed_by_idx on public.sector_partner_registration_requests(reviewed_by) where reviewed_by is not null;

drop policy if exists guardian_relationships_update_admin on public.guardian_relationships;
drop policy if exists guardian_relationships_update_owner_pending on public.guardian_relationships;
create policy guardian_relationships_update on public.guardian_relationships for update to authenticated
using (private.is_admin_user() or (learner_id=(select auth.uid()) and status='pending'))
with check (private.is_admin_user() or (learner_id=(select auth.uid()) and status='pending'));
;

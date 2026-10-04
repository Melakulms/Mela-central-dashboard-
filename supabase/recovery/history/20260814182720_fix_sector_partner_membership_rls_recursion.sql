-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814182720
create or replace function private.has_sector_partner_membership(p_org_id uuid,p_user_id uuid,p_admin_only boolean default false)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists(
    select 1 from public.sector_partner_members m
    where m.partner_organization_id=p_org_id
      and m.user_id=p_user_id
      and m.status='active'
      and (not p_admin_only or m.member_role in ('owner','admin'))
  );
$function$;
revoke all on function private.has_sector_partner_membership(uuid,uuid,boolean) from public,anon;
grant execute on function private.has_sector_partner_membership(uuid,uuid,boolean) to authenticated,service_role;

drop policy if exists sector_partner_org_read on public.sector_partner_organizations;
create policy sector_partner_org_read on public.sector_partner_organizations for select to authenticated using(
  verification_status='verified'
  or owner_id=(select auth.uid())
  or private.is_admin_user()
  or private.has_sector_partner_membership(id,(select auth.uid()),false)
);

drop policy if exists sector_partner_members_read on public.sector_partner_members;
create policy sector_partner_members_read on public.sector_partner_members for select to authenticated using(
  user_id=(select auth.uid())
  or private.is_admin_user()
  or private.has_sector_partner_membership(partner_organization_id,(select auth.uid()),true)
);
;

-- Generic legacy overrides are super-admin operations, not profile labels.
-- Granular roles continue through permission-checked Central Admin APIs.
set lock_timeout='5s';
alter table admin.admin_users add constraint active_admin_requires_mfa
  check (not active or mfa_required);
create or replace function private.is_admin_user()
returns boolean language sql stable security definer set search_path='' as $$
  select
    (session_user in ('postgres','service_role','supabase_auth_admin')
      and coalesce(current_setting('role',true),'none') in ('none','postgres','service_role','supabase_auth_admin')
      and (select auth.uid()) is null)
    or coalesce((select auth.jwt()->>'role')='service_role',false)
    or exists (
      select 1 from admin.admin_users au
      join admin.roles ar on ar.id=au.role_id and ar.key='super_admin'
      join public.profiles p on p.id=au.user_id
      where au.user_id=(select auth.uid()) and au.active and au.mfa_required
        and p.account_status='active' and p.deleted_at is null
        and coalesce((select auth.jwt()->>'aal'),'aal1')='aal2'
    );
$$;
comment on function private.is_admin_user() is
  'Trusted maintenance/service or active registry super-admin with AAL2. Profile role labels and granular admin roles do not grant generic overrides.';

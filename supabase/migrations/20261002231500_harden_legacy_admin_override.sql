-- Legacy browser-callable RPCs use private.is_admin_user() as a broad override.
-- Bind that override to the central admin control plane so a profile role alone
-- cannot bypass admin membership, MFA, or role separation.
CREATE OR REPLACE FUNCTION private.is_admin_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  select
    -- Preserve trusted database/Auth maintenance callers that do not represent
    -- an end-user JWT session.
    (
      session_user in ('postgres','service_role','supabase_auth_admin')
      and coalesce(current_setting('role', true), 'none') in ('none','postgres','service_role','supabase_auth_admin')
      and (select auth.uid()) is null
    )
    -- Preserve service-role requests without relying on the deprecated auth.role().
    or coalesce((select auth.jwt() ->> 'role') = 'service_role', false)
    -- A generic legacy admin override is intentionally restricted to an active
    -- central super-admin. Granular admin roles must use the permissioned admin API.
    or exists (
      select 1
      from public.profiles p
      join admin.admin_users au
        on au.user_id = p.id
       and au.active
      join admin.roles ar
        on ar.id = au.role_id
       and ar.key = 'super_admin'
      where p.id = (select auth.uid())
        and p.role = 'admin'::public.user_role
        and p.account_status = 'active'
        and p.deleted_at is null
        and (
          not au.mfa_required
          or coalesce((select auth.jwt() ->> 'aal'), '') = 'aal2'
        )
    )
$function$;

COMMENT ON FUNCTION private.is_admin_user() IS
  'Trusted-service or central super-admin authorization helper. Interactive admins require active central membership and AAL2 when MFA is required.';

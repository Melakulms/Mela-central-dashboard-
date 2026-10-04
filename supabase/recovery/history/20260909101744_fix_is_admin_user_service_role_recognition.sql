-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260909101744

-- Bug: private.is_admin_user() only checked auth.uid() against profiles.role='admin'.
-- Every mela-admin-api / mela-ai-admin action runs through a service-role client
-- (adminDb = createClient(url, SERVICE_ROLE_KEY)) with NO bound user JWT, so
-- auth.uid() is NULL in that context and is_admin_user() always returned false.
--
-- is_admin_user() gates 20+ BEFORE UPDATE trigger guards across profiles,
-- opportunities, reports, mentor verification, payouts, subscriptions, and
-- freelance contract/milestone financial fields (guard_*, protect_*, enforce_*
-- functions). Confirmed by reproduction: attempting the exact SQL that
-- mela-admin-api's user.update action runs (updating profiles.account_status)
-- failed with "protected profile role, trust, authentication, or account-state
-- fields can only be changed by authorized system operations" -- meaning the
-- real admin dashboard's suspend/verify/role-change actions, and likely several
-- other admin review actions, were silently broken in production.
--
-- Fix: recognize the service_role connection itself as admin-equivalent, since
-- it is only ever available to trusted backend code (Edge Functions) that has
-- already performed its own RBAC/MFA checks before reaching this point. This
-- does not weaken protection for regular authenticated users -- they still
-- cannot touch these fields directly; only the already-authorized backend path
-- is unblocked. service_role already bypasses RLS entirely (BYPASSRLS) but
-- triggers are a separate enforcement layer that BYPASSRLS does not skip,
-- which is why this was blocking even the legitimate admin backend.

CREATE OR REPLACE FUNCTION private.is_admin_user()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select (select auth.role()) = 'service_role'
     or coalesce((select p.role='admin'::public.user_role from public.profiles p where p.id=(select auth.uid())), false)
$function$;

;

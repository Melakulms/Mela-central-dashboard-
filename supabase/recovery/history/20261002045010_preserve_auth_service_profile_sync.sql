-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002045010
CREATE OR REPLACE FUNCTION private.is_admin_user()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select
    (session_user in ('postgres','service_role','supabase_auth_admin')
      and coalesce(current_setting('role', true), 'none') in ('none','postgres','service_role','supabase_auth_admin')
      and (select auth.uid()) is null)
    or coalesce((select auth.role()) = 'service_role', false)
    or exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.role = 'admin'::public.user_role
        and p.account_status = 'active' and p.deleted_at is null
    )
$function$;


;

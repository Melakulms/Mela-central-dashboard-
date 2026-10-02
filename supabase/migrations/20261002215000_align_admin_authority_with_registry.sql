-- Production-applied: align database admin authorization with the dedicated
-- admin.admin_users registry and MFA assurance, without mutating learner roles.

create or replace function private.is_admin_user()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select
    (session_user in ('postgres','service_role','supabase_auth_admin')
      and coalesce(current_setting('role', true), 'none') in ('none','postgres','service_role','supabase_auth_admin')
      and (select auth.uid()) is null)
    or coalesce((select auth.role()) = 'service_role', false)
    or exists (
      select 1
      from admin.admin_users au
      join public.profiles p on p.id=au.user_id
      where au.user_id=(select auth.uid())
        and au.active=true
        and p.account_status='active'
        and p.deleted_at is null
        and (au.mfa_required=false or coalesce((select auth.jwt())->>'aal','aal1')='aal2')
    )
    or exists (
      select 1
      from public.profiles p
      where p.id=(select auth.uid())
        and p.role='admin'::public.user_role
        and p.account_status='active'
        and p.deleted_at is null
        and coalesce((select auth.jwt())->>'aal','aal1')='aal2'
    );
$function$;

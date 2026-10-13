-- Executed on MELA production as migration 20261013195132.
-- Align review access with Central Dashboard teacher verification decisions.
create or replace function public.mela_is_verified_teacher()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1
    from public.teacher_profiles t
    join public.profiles p on p.id=t.user_id
    where t.user_id=(select auth.uid())
      and t.verification_status in ('approved','verified')
      and t.verified_by is not null
      and t.verified_at is not null
      and p.role='teacher'::public.user_role
      and p.account_status='active'
      and p.email_verified=true
  );
$function$;

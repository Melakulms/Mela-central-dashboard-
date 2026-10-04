-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260816062914
create or replace function public.get_my_access_context_v35()
returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object(
   'user_id',p.id,'role',p.role,'role_selected_at',p.role_selected_at,'account_status',p.account_status,
   'verified',(p.email_verified or p.phone_verified),'email_verified',p.email_verified,'phone_verified',p.phone_verified,
   'profile_completion',p.profile_completion,'onboarding_step',p.onboarding_step,
   'subscription',coalesce((select jsonb_build_object('status',us.status,'tier',sp.tier,'plan_key',sp.plan_key,'expires_at',us.expires_at)
      from public.user_subscriptions us join public.subscription_plans sp on sp.id=us.plan_id
      where us.user_id=p.id and us.status in ('free','premium_pending','premium_active') order by us.created_at desc limit 1),jsonb_build_object('status','free','tier','free'))
 ) from public.profiles p where p.id=(select auth.uid());
$$;
revoke all on function public.get_my_access_context_v35() from public,anon;
grant execute on function public.get_my_access_context_v35() to authenticated;
;

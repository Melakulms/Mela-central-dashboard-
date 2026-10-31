-- Read-only billing queue for an independently verified, MFA-authenticated payment administrator.
create or replace function public.mela_billing_admin_list_v1()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare u uuid:=auth.uid();
begin
 if u is null or (auth.jwt()->>'aal') is distinct from 'aal2'
 or coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
 or not exists(select 1 from admin.admin_users where user_id=u and active)
 or not exists(select 1 from auth.mfa_factors where user_id=u and status='verified')
 or not exists(select 1 from auth.sessions where id::text=auth.jwt()->>'session_id'
   and user_id=u and (not_after is null or not_after>now()))
 then raise exception 'MFA-verified payment administrator required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(x) from
   (select id,user_id,plan_key,amount_minor,currency,method_code,recipient,
      claimed_reference,status,created_at,reviewed_at,review_note
    from mela_billing.orders order by (status='pending_review') desc,created_at desc limit 100) x),'[]'::jsonb);
end $$;
revoke all on function public.mela_billing_admin_list_v1() from public,anon;
grant execute on function public.mela_billing_admin_list_v1() to authenticated;

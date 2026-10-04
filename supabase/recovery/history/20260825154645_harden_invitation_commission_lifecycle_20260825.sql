-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825154645
begin;

create or replace function public.mark_invitation_commission_paid(p_commission_id uuid, p_actor_id uuid default null)
returns public.invitation_commissions
language plpgsql
security definer
set search_path = ''
as $$
declare v public.invitation_commissions;
begin
  if p_commission_id is null then raise exception 'Commission ID is required'; end if;
  select * into v from public.invitation_commissions where id=p_commission_id for update;
  if v.id is null then raise exception 'Commission not found'; end if;
  if v.status='cancelled' then raise exception 'Cancelled commission cannot be paid'; end if;
  if v.status='paid' then return v; end if;
  if v.status not in ('pending','eligible') then raise exception 'Invalid commission state: %', v.status; end if;

  update public.invitation_commissions
  set status='paid', paid_at=coalesce(paid_at,now())
  where id=v.id and status in ('pending','eligible');

  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
  values(p_actor_id,'mark_invitation_commission_paid','invitation_commission',v.id,jsonb_build_object('amount',v.amount,'currency',v.currency,'previous_status',v.status));

  select * into v from public.invitation_commissions where id=p_commission_id;
  return v;
end;
$$;

revoke all on function public.mark_invitation_commission_paid(uuid,uuid) from public, anon, authenticated;

create or replace function public.cancel_invitation_commission(p_commission_id uuid, p_reason text, p_actor_id uuid default null)
returns public.invitation_commissions
language plpgsql
security definer
set search_path = ''
as $$
declare v public.invitation_commissions; l public.earnings_ledger;
begin
  if p_commission_id is null then raise exception 'Commission ID is required'; end if;
  if p_reason is null or length(trim(p_reason)) < 5 then raise exception 'Cancellation reason is required'; end if;
  select * into v from public.invitation_commissions where id=p_commission_id for update;
  if v.id is null then raise exception 'Commission not found'; end if;
  if v.status='cancelled' then raise exception 'Commission is already cancelled'; end if;

  select * into l from public.earnings_ledger where source_type='referral_reward' and source_id=v.id order by created_at desc limit 1 for update;
  if l.id is not null and l.status not in ('available','pending','reversed') then raise exception 'Commission cannot be cancelled because earnings are committed to a payout'; end if;

  update public.invitation_commissions set status='cancelled',cancelled_at=now(),cancellation_reason=left(trim(p_reason),500) where id=v.id;
  if l.id is not null and l.status <> 'reversed' then update public.earnings_ledger set status='reversed',net_amount=0,platform_fee=0,occurred_at=now() where id=l.id; end if;
  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details) values(p_actor_id,'cancel_invitation_commission','invitation_commission',v.id,jsonb_build_object('reason',left(trim(p_reason),500),'previous_status',v.status));
  select * into v from public.invitation_commissions where id=p_commission_id;
  return v;
end;
$$;

revoke all on function public.cancel_invitation_commission(uuid,text,uuid) from public, anon, authenticated;
commit;
;

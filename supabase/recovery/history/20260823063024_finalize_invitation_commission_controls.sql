-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260823063024
drop function if exists public.cancel_invitation_commission(uuid,text);

create or replace function public.cancel_invitation_commission(p_commission_id uuid, p_reason text, p_actor_id uuid default null)
returns public.invitation_commissions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.invitation_commissions;
  v_ledger public.earnings_ledger;
  v_previous_status text;
begin
  if p_commission_id is null then raise exception 'Commission ID is required'; end if;
  if p_reason is null or length(trim(p_reason)) < 5 then raise exception 'Cancellation reason is required'; end if;

  select * into v_row from public.invitation_commissions where id=p_commission_id for update;
  if v_row.id is null then raise exception 'Commission not found'; end if;
  if v_row.status='cancelled' then raise exception 'Commission is already cancelled'; end if;
  v_previous_status:=v_row.status;

  select * into v_ledger
  from public.earnings_ledger
  where source_type='referral_reward' and source_id=v_row.id
  order by created_at desc limit 1
  for update;

  if v_ledger.id is not null and v_ledger.status not in ('available','pending','reversed') then
    raise exception 'Commission cannot be cancelled because its earnings are already committed to a payout';
  end if;

  update public.invitation_commissions
  set status='cancelled', cancelled_at=now(), cancellation_reason=left(trim(p_reason),500)
  where id=v_row.id;

  if v_ledger.id is not null and v_ledger.status <> 'reversed' then
    update public.earnings_ledger
    set status='reversed', net_amount=0, platform_fee=0, occurred_at=now()
    where id=v_ledger.id;
  end if;

  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
  values(p_actor_id,'cancel_invitation_commission','invitation_commission',v_row.id,
    jsonb_build_object('reason',left(trim(p_reason),500),'transaction_reference',v_row.transaction_reference,'previous_status',v_previous_status));

  select * into v_row from public.invitation_commissions where id=p_commission_id;
  return v_row;
end;
$$;
revoke all on function public.cancel_invitation_commission(uuid,text,uuid) from public,anon,authenticated;

create index if not exists invitation_commissions_registered_idx on public.invitation_commissions(registered_user_id,created_at desc);
create index if not exists earnings_ledger_referral_status_idx on public.earnings_ledger(source_type,status,created_at desc) where source_type='referral_reward';
;

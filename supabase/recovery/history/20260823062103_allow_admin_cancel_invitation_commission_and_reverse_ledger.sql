-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260823062103
create or replace function public.cancel_invitation_commission(p_commission_id uuid, p_reason text)
returns public.invitation_commissions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_comm public.invitation_commissions;
  v_ledger public.earnings_ledger;
begin
  if p_commission_id is null then raise exception 'Commission ID is required'; end if;
  if p_reason is null or length(trim(p_reason)) < 5 then raise exception 'Cancellation reason is required'; end if;
  select * into v_comm from public.invitation_commissions where id=p_commission_id for update;
  if v_comm.id is null then raise exception 'Commission not found'; end if;
  if v_comm.status='cancelled' then raise exception 'Commission is already cancelled'; end if;

  select * into v_ledger
  from public.earnings_ledger
  where source_type='referral_reward' and source_id=v_comm.id
  order by created_at desc limit 1
  for update;

  if v_ledger.id is not null and v_ledger.status not in ('available','pending','reversed') then
    raise exception 'Commission cannot be cancelled because its ledger balance is already committed to a payout';
  end if;

  update public.invitation_commissions
  set status='cancelled', cancelled_at=now(), cancellation_reason=left(trim(p_reason),500)
  where id=v_comm.id;

  if v_ledger.id is not null and v_ledger.status <> 'reversed' then
    update public.earnings_ledger
    set status='reversed', net_amount=0, platform_fee=0
    where id=v_ledger.id;
  end if;

  select * into v_comm from public.invitation_commissions where id=p_commission_id;
  return v_comm;
end;
$$;
revoke all on function public.cancel_invitation_commission(uuid,text) from public, anon, authenticated;
;

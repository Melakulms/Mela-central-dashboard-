-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260823061137
create or replace function public.cancel_invitation_commission(p_commission_id uuid,p_reason text,p_actor_id uuid default null)
returns public.invitation_commissions
language plpgsql
security definer
set search_path=public
as $$
declare v_row public.invitation_commissions; v_ledger public.earnings_ledger;
begin
  if p_reason is null or length(trim(p_reason)) < 5 then raise exception 'Cancellation reason is required'; end if;
  update public.invitation_commissions
    set status='cancelled',cancelled_at=now(),cancellation_reason=left(trim(p_reason),500)
    where id=p_commission_id and status in ('pending','paid')
    returning * into v_row;
  if v_row.id is null then raise exception 'Commission not found or already cancelled'; end if;
  update public.earnings_ledger
    set status='reversed',occurred_at=now()
    where source_type='referral_reward' and source_id=v_row.id and status <> 'reversed'
    returning * into v_ledger;
  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
  values(p_actor_id,'cancel_invitation_commission','invitation_commission',v_row.id,jsonb_build_object('reason',left(trim(p_reason),500),'transaction_reference',v_row.transaction_reference,'previous_status',case when v_row.paid_at is null then 'pending' else 'paid' end));
  return v_row;
end;
$$;
revoke all on function public.cancel_invitation_commission(uuid,text,uuid) from public,anon,authenticated;
;

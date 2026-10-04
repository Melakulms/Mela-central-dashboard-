-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812215743
-- Preserve legacy escrow states while allowing the new workflow state used by active finance Edge Functions.
alter table public.escrow_transactions drop constraint if exists escrow_status_chk;
alter table public.escrow_transactions add constraint escrow_status_chk check (
  status in ('pending_funding','funding_pending','awaiting_funding','held','release_pending','released','refund_pending','refunded','disputed','failed','cancelled')
);

create or replace function private.sync_escrow_from_milestone()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare v_contract public.freelance_contracts%rowtype; v_task public.marketplace_tasks%rowtype;
begin
  select * into v_contract from public.freelance_contracts where id=new.contract_id;
  select * into v_task from public.marketplace_tasks where id=v_contract.task_id;
  if tg_op='INSERT' then
    insert into public.escrow_transactions(task_id,user_id,amount_coins,status,contract_id,amount_minor,currency,provider,milestone_id)
    values(v_contract.task_id,v_contract.freelancer_id,coalesce(v_task.reward_coins,0),'pending_funding',v_contract.id,round(new.amount*100)::bigint,v_contract.currency,'chapa',new.id)
    on conflict (milestone_id) where milestone_id is not null do nothing;
  elsif new.amount is distinct from old.amount then
    update public.escrow_transactions
      set amount_minor=round(new.amount*100)::bigint,updated_at=now()
    where milestone_id=new.id and status in ('pending_funding','funding_pending','awaiting_funding');
  end if;
  return new;
end;$$;
revoke all on function private.sync_escrow_from_milestone() from public,anon,authenticated;

;

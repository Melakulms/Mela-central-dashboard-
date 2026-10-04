-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813104557
update public.escrow_transactions set status='funding_pending',updated_at=now() where transaction_type='funding' and milestone_id is not null and status='pending_funding';

create or replace function private.sync_escrow_from_milestone()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_contract public.freelance_contracts%rowtype;
  v_task public.marketplace_tasks%rowtype;
begin
  select * into v_contract from public.freelance_contracts where id=new.contract_id;
  select * into v_task from public.marketplace_tasks where id=v_contract.task_id;
  if tg_op='INSERT' then
    insert into public.escrow_transactions(task_id,user_id,amount_coins,status,contract_id,amount_minor,currency,provider,milestone_id,transaction_type,payer_employer_id)
    values(v_contract.task_id,v_contract.freelancer_id,coalesce(v_task.reward_coins,0),'funding_pending',v_contract.id,round(new.amount*100)::bigint,v_contract.currency,'chapa',new.id,'funding',v_contract.employer_id)
    on conflict (milestone_id) where transaction_type='funding' and milestone_id is not null do nothing;
  elsif new.amount is distinct from old.amount then
    update public.escrow_transactions set amount_minor=round(new.amount*100)::bigint,updated_at=now()
    where milestone_id=new.id and transaction_type='funding' and status in ('funding_pending','failed');
  end if;
  return new;
end;
$function$;

create or replace function public.record_escrow_funding(p_contract_id uuid,p_amount_minor bigint,p_provider text,p_external_ref text)
returns public.freelance_contracts
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_c public.freelance_contracts%rowtype;
  v_escrow_id uuid;
  v_count integer;
begin
  if p_amount_minor<=0 then raise exception 'funding amount must be positive'; end if;
  select * into v_c from public.freelance_contracts where id=p_contract_id for update;
  if not found or v_c.status<>'active' then raise exception 'active contract not found'; end if;

  if nullif(trim(coalesce(p_external_ref,'')),'') is not null then
    select a.escrow_id into v_escrow_id
    from public.escrow_payment_attempts a
    join public.escrow_transactions e on e.id=a.escrow_id
    where a.tx_ref=p_external_ref and e.contract_id=p_contract_id and e.transaction_type='funding' and e.milestone_id is not null
    limit 1;
  end if;

  if v_escrow_id is null then
    select count(*),min(id) into v_count,v_escrow_id
    from public.escrow_transactions
    where contract_id=p_contract_id and transaction_type='funding' and milestone_id is not null
      and status in ('funding_pending','failed') and amount_minor=p_amount_minor;
    if v_count<>1 then raise exception 'unable to resolve the exact milestone escrow; use escrow-specific funding'; end if;
  end if;

  perform public.record_milestone_escrow_funding(v_escrow_id,p_amount_minor,p_provider,p_external_ref);
  select * into v_c from public.freelance_contracts where id=p_contract_id;
  return v_c;
end;
$function$;
revoke all on function public.record_escrow_funding(uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.record_escrow_funding(uuid,bigint,text,text) to service_role;
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813103510
drop index if exists public.escrow_one_funding_per_contract;
create unique index if not exists escrow_one_funding_per_milestone
  on public.escrow_transactions(milestone_id)
  where transaction_type='funding' and milestone_id is not null;
create unique index if not exists escrow_one_legacy_contract_funding
  on public.escrow_transactions(contract_id)
  where transaction_type='funding' and milestone_id is null and contract_id is not null;

create or replace function private.refresh_contract_finance_from_escrow()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_contract_id uuid := coalesce(new.contract_id,old.contract_id);
  v_agreed numeric;
  v_funded numeric := 0;
  v_released numeric := 0;
  v_has_pending boolean := false;
  v_status text;
begin
  if v_contract_id is null then return coalesce(new,old); end if;

  select agreed_amount into v_agreed from public.freelance_contracts where id=v_contract_id;
  if v_agreed is null then return coalesce(new,old); end if;

  select
    coalesce(sum(amount_minor) filter (where transaction_type='funding' and milestone_id is not null and status in ('held','released')),0)::numeric/100,
    coalesce(sum(amount_minor) filter (where transaction_type='funding' and milestone_id is not null and status='released'),0)::numeric/100,
    exists(select 1 from public.escrow_transactions e2 where e2.contract_id=v_contract_id and e2.transaction_type='funding' and e2.milestone_id is not null and e2.status in ('pending_funding','funding_pending','failed'))
  into v_funded,v_released,v_has_pending
  from public.escrow_transactions e
  where e.contract_id=v_contract_id;

  v_status := case
    when v_agreed>0 and v_released>=v_agreed then 'released'
    when v_released>0 then 'partially_released'
    when v_agreed>0 and v_funded>=v_agreed then 'held'
    when v_funded>0 or v_has_pending then 'pending'
    else 'unfunded'
  end;

  update public.freelance_contracts
  set funded_amount=v_funded,
      released_amount=v_released,
      funding_status=v_status,
      updated_at=now()
  where id=v_contract_id;

  return coalesce(new,old);
end;
$function$;

drop trigger if exists trg_refresh_contract_finance_from_escrow on public.escrow_transactions;
create trigger trg_refresh_contract_finance_from_escrow
after insert or update of status,amount_minor or delete on public.escrow_transactions
for each row execute function private.refresh_contract_finance_from_escrow();

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
    insert into public.escrow_transactions(
      task_id,user_id,amount_coins,status,contract_id,amount_minor,currency,provider,
      milestone_id,transaction_type,payer_employer_id
    ) values (
      v_contract.task_id,v_contract.freelancer_id,coalesce(v_task.reward_coins,0),'pending_funding',
      v_contract.id,round(new.amount*100)::bigint,v_contract.currency,'chapa',new.id,'funding',v_contract.employer_id
    )
    on conflict (milestone_id) where transaction_type='funding' and milestone_id is not null do nothing;
  elsif new.amount is distinct from old.amount then
    update public.escrow_transactions
    set amount_minor=round(new.amount*100)::bigint,updated_at=now()
    where milestone_id=new.id and transaction_type='funding'
      and status in ('pending_funding','funding_pending','failed');
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_sync_escrow_from_milestone on public.task_milestones;
create trigger trg_sync_escrow_from_milestone
after insert or update of amount on public.task_milestones
for each row execute function private.sync_escrow_from_milestone();

create or replace function private.respond_freelance_contract(p_contract_id uuid, p_accept boolean, p_reason text default null::text)
returns public.freelance_contracts
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_c public.freelance_contracts%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_c from public.freelance_contracts where id=p_contract_id for update;
  if not found then raise exception 'contract not found'; end if;
  if v_c.freelancer_id<>v_uid then raise exception 'only the selected freelancer can respond'; end if;
  if v_c.status<>'proposed' then raise exception 'contract is no longer awaiting response'; end if;

  if p_accept then
    update public.freelance_contracts
    set status='active',accepted_at=now(),started_at=now(),updated_at=now(),
        funding_status=case when exists(select 1 from public.task_milestones m where m.contract_id=p_contract_id) then 'pending' else 'unfunded' end
    where id=p_contract_id returning * into v_c;
    update public.marketplace_tasks set status='in_progress',assigned_to=v_uid,updated_at=now() where id=v_c.task_id;
    perform private.notify_employer_owner(v_c.employer_id,'Freelance contract accepted','The selected freelancer accepted the contract. Create and fund milestone escrow before approval.','freelance_contracts',v_c.id);
  else
    update public.freelance_contracts
    set status='cancelled',cancelled_at=now(),cancellation_reason=coalesce(nullif(trim(coalesce(p_reason,'')),''),'declined_by_freelancer'),updated_at=now()
    where id=p_contract_id returning * into v_c;
    update public.marketplace_tasks set status='open',assigned_to=null,updated_at=now() where id=v_c.task_id;
    update public.marketplace_submissions set status='rejected',reviewed_at=now(),updated_at=now() where task_id=v_c.task_id and user_id=v_c.freelancer_id;
    perform private.notify_employer_owner(v_c.employer_id,'Freelance contract declined','The selected freelancer declined the proposed contract. The task was reopened.','freelance_contracts',v_c.id);
  end if;
  return v_c;
end;
$function$;

create or replace function private.process_milestone_status()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $function$
declare
  v_contract public.freelance_contracts%rowtype;
begin
  if new.status is not distinct from old.status then return new; end if;
  select * into v_contract from public.freelance_contracts where id=new.contract_id;

  if new.status='submitted' then
    perform private.create_notification((select posted_by from public.marketplace_tasks where id=v_contract.task_id),'Freelance milestone submitted','The freelancer submitted a milestone for review.','task_milestones',new.id);
  elsif new.status='rejected' then
    perform private.create_notification(v_contract.freelancer_id,'Freelance milestone needs changes',coalesce(new.review_note,new.review_notes,'The employer requested revisions.'),'task_milestones',new.id);
  elsif new.status='approved' then
    perform private.create_notification(v_contract.freelancer_id,'Milestone approved','Your milestone was approved and is ready for the protected payout workflow.','task_milestones',new.id);
  elsif new.status='paid' then
    perform private.create_notification(v_contract.freelancer_id,'Freelance payout completed','Payment for your milestone was released.','task_milestones',new.id);
  end if;
  return new;
end;
$function$;

create or replace function private.review_task_milestone(p_milestone_id uuid, p_decision text, p_notes text default null::text)
returns public.task_milestones
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_m public.task_milestones%rowtype;
  v_c public.freelance_contracts%rowtype;
  v_escrow public.escrow_transactions%rowtype;
  v_ref text;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'decision must be approved or rejected'; end if;

  select * into v_m from public.task_milestones where id=p_milestone_id for update;
  if not found or v_m.status<>'submitted' then raise exception 'submitted milestone required'; end if;
  select * into v_c from public.freelance_contracts where id=v_m.contract_id;
  if not private.has_employer_access(v_c.employer_id,true) then raise exception 'not authorized'; end if;

  if p_decision='approved' then
    select * into v_escrow
    from public.escrow_transactions
    where milestone_id=v_m.id and transaction_type='funding' and status='held'
    limit 1;
    if not found then raise exception 'milestone escrow must be funded before approval'; end if;
    if coalesce(v_escrow.amount_minor,0) < round(v_m.amount*100)::bigint then raise exception 'funded escrow is below milestone amount'; end if;
  end if;

  update public.task_milestones
  set status=p_decision,
      approved_at=case when p_decision='approved' then now() else null end,
      reviewed_by=v_uid,
      review_notes=nullif(trim(coalesce(p_notes,'')),''),
      review_note=nullif(trim(coalesce(p_notes,'')),''),
      updated_at=now()
  where id=p_milestone_id
  returning * into v_m;

  if p_decision='approved' then
    if not exists(select 1 from public.payout_requests p where p.milestone_id=v_m.id and p.status in ('pending','queued','success')) then
      v_ref := 'mela_payout_'||replace(gen_random_uuid()::text,'-','');
      insert into public.payout_requests(milestone_id,escrow_id,freelancer_id,amount_minor,currency,payout_ref,status)
      values(v_m.id,v_escrow.id,v_c.freelancer_id,round(v_m.amount*100)::bigint,v_c.currency,v_ref,'pending');
    end if;
  end if;

  return v_m;
end;
$function$;

create or replace function public.record_escrow_funding(p_contract_id uuid, p_amount_minor bigint, p_provider text, p_external_ref text)
returns public.freelance_contracts
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_c public.freelance_contracts%rowtype;
  v_e public.escrow_transactions%rowtype;
  v_count integer;
begin
  if p_amount_minor<=0 then raise exception 'funding amount must be positive'; end if;
  select * into v_c from public.freelance_contracts where id=p_contract_id for update;
  if not found or v_c.status<>'active' then raise exception 'active contract not found'; end if;

  select count(*) into v_count from public.escrow_transactions
  where contract_id=p_contract_id and transaction_type='funding' and milestone_id is not null
    and status in ('pending_funding','funding_pending','failed');
  if v_count<>1 then raise exception 'contract has % fundable milestones; use the escrow-specific finance workflow',v_count; end if;

  select * into v_e from public.escrow_transactions
  where contract_id=p_contract_id and transaction_type='funding' and milestone_id is not null
    and status in ('pending_funding','funding_pending','failed')
  for update;

  if v_e.amount_minor<>p_amount_minor then raise exception 'funding amount must exactly match milestone escrow'; end if;

  update public.escrow_transactions
  set status='held',provider=p_provider,external_ref=p_external_ref,funded_at=now(),updated_at=now()
  where id=v_e.id;

  select * into v_c from public.freelance_contracts where id=p_contract_id;
  return v_c;
end;
$function$;

create or replace function public.record_milestone_payout(p_milestone_id uuid, p_provider text, p_external_ref text)
returns public.task_milestones
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_m public.task_milestones%rowtype;
  v_c public.freelance_contracts%rowtype;
  v_e public.escrow_transactions%rowtype;
begin
  select * into v_m from public.task_milestones where id=p_milestone_id for update;
  if not found or v_m.status<>'approved' then raise exception 'approved milestone required'; end if;
  select * into v_c from public.freelance_contracts where id=v_m.contract_id for update;
  select * into v_e from public.escrow_transactions
  where milestone_id=v_m.id and transaction_type='funding' and status='held'
  limit 1 for update;
  if not found then raise exception 'funded milestone escrow not found'; end if;

  update public.escrow_transactions
  set status='released',provider=p_provider,external_ref=p_external_ref,payout_ref=p_external_ref,released_at=now(),updated_at=now()
  where id=v_e.id;

  update public.task_milestones set status='paid',updated_at=now() where id=p_milestone_id returning * into v_m;

  update public.payout_requests
  set status='success',provider=p_provider,provider_ref=p_external_ref,completed_at=now(),updated_at=now()
  where milestone_id=p_milestone_id and status in ('pending','queued','failed');

  if not exists(select 1 from public.task_milestones m where m.contract_id=v_c.id and m.status<>'paid') then
    update public.freelance_contracts set status='completed',completed_at=now(),updated_at=now() where id=v_c.id;
    update public.marketplace_tasks set status='completed',updated_at=now() where id=v_c.task_id;
  end if;

  return v_m;
end;
$function$;

-- Align existing milestone escrow rows with the canonical per-milestone model.
update public.escrow_transactions e
set transaction_type='funding',
    amount_minor=round(m.amount*100)::bigint,
    payer_employer_id=c.employer_id,
    updated_at=now()
from public.task_milestones m
join public.freelance_contracts c on c.id=m.contract_id
where e.milestone_id=m.id and e.contract_id=c.id;

;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813102709
drop trigger if exists trg_sync_escrow_from_milestone on public.task_milestones;
drop index if exists public.escrow_milestone_uidx;

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
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'decision must be approved or rejected'; end if;
  select * into v_m from public.task_milestones where id=p_milestone_id for update;
  if not found or v_m.status<>'submitted' then raise exception 'submitted milestone required'; end if;
  select * into v_c from public.freelance_contracts where id=v_m.contract_id;
  if not private.has_employer_access(v_c.employer_id,true) then raise exception 'not authorized'; end if;

  if p_decision='approved' then
    insert into public.escrow_transactions(task_id,user_id,amount_coins,status,contract_id,milestone_id,amount_minor,currency,transaction_type,payer_employer_id,updated_at)
    values(v_c.task_id,v_c.freelancer_id,0,case when v_c.funding_status in ('held','partially_released') then 'release_pending' else 'awaiting_funding' end,v_c.id,v_m.id,round(v_m.amount*100)::bigint,v_c.currency,'release',v_c.employer_id,now())
    on conflict (milestone_id) where transaction_type='release' and milestone_id is not null do update
      set amount_minor=excluded.amount_minor,
          currency=excluded.currency,
          status=excluded.status,
          payer_employer_id=excluded.payer_employer_id,
          updated_at=now();
  end if;

  update public.task_milestones
  set status=p_decision,
      approved_at=case when p_decision='approved' then now() else null end,
      reviewed_by=v_uid,
      review_notes=nullif(trim(coalesce(p_notes,'')),''),
      updated_at=now()
  where id=p_milestone_id
  returning * into v_m;

  insert into public.notifications(user_id,title,body,ref_table,ref_id)
  values(v_c.freelancer_id,'Milestone review','Your milestone was '||p_decision||'.','task_milestones',v_m.id);
  return v_m;
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
  v_escrow uuid;
  v_minor bigint;
  v_ref text;
begin
  if new.status is not distinct from old.status then return new; end if;
  select * into v_contract from public.freelance_contracts where id=new.contract_id;
  if new.status='submitted' then
    perform private.create_notification((select posted_by from public.marketplace_tasks where id=v_contract.task_id),'Freelance milestone submitted','The freelancer submitted a milestone for review.','task_milestones',new.id);
  elsif new.status='rejected' then
    perform private.create_notification(v_contract.freelancer_id,'Freelance milestone needs changes',coalesce(new.review_note,new.review_notes,'The employer requested revisions.'),'task_milestones',new.id);
  elsif new.status='approved' then
    select id,amount_minor into v_escrow,v_minor
    from public.escrow_transactions
    where milestone_id=new.id and transaction_type='release' and status='release_pending'
    limit 1;
    if v_escrow is not null and v_minor is not null and v_minor>0 then
      v_ref:='mela_payout_'||replace(gen_random_uuid()::text,'-','');
      insert into public.payout_requests(milestone_id,escrow_id,freelancer_id,amount_minor,currency,payout_ref,status)
      values(new.id,v_escrow,v_contract.freelancer_id,v_minor,v_contract.currency,v_ref,'pending')
      on conflict do nothing;
    end if;
    perform private.create_notification(v_contract.freelancer_id,'Milestone approved','Your milestone was approved. Payout is being prepared.','task_milestones',new.id);
  elsif new.status='paid' then
    perform private.create_notification(v_contract.freelancer_id,'Freelance payout completed','Payment for your milestone was released.','task_milestones',new.id);
  end if;
  return new;
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
  v_amount numeric;
  v_r record;
begin
  if p_amount_minor<=0 then raise exception 'funding amount must be positive'; end if;
  select * into v_c from public.freelance_contracts where id=p_contract_id for update;
  if not found or v_c.status<>'active' then raise exception 'active contract not found'; end if;
  v_amount:=p_amount_minor::numeric/100;
  if v_amount<v_c.agreed_amount then raise exception 'funding amount is below agreed contract amount'; end if;

  update public.freelance_contracts
  set funded_amount=v_amount,
      funding_status=case when released_amount>0 then 'partially_released' else 'held' end,
      updated_at=now()
  where id=p_contract_id
  returning * into v_c;

  update public.escrow_transactions
  set status='held',provider=p_provider,external_ref=p_external_ref,amount_minor=p_amount_minor,funded_at=coalesce(funded_at,now()),updated_at=now()
  where contract_id=p_contract_id and transaction_type='funding';

  update public.escrow_transactions
  set status='release_pending',updated_at=now()
  where contract_id=p_contract_id and transaction_type='release' and status='awaiting_funding';

  for v_r in
    select m.id milestone_id,e.id escrow_id,e.amount_minor,e.currency
    from public.task_milestones m
    join public.escrow_transactions e on e.milestone_id=m.id and e.transaction_type='release' and e.status='release_pending'
    where m.contract_id=p_contract_id and m.status='approved'
      and not exists(select 1 from public.payout_requests pr where pr.milestone_id=m.id and pr.status in ('pending','queued','success'))
  loop
    insert into public.payout_requests(milestone_id,escrow_id,freelancer_id,amount_minor,currency,payout_ref,status)
    values(v_r.milestone_id,v_r.escrow_id,v_c.freelancer_id,v_r.amount_minor,v_r.currency,'mela_payout_'||replace(gen_random_uuid()::text,'-',''),'pending')
    on conflict do nothing;
  end loop;

  return v_c;
end;
$function$;

revoke all on function public.record_escrow_funding(uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.record_escrow_funding(uuid,bigint,text,text) to service_role;

;

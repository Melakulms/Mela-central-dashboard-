-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813104516
create or replace function public.record_milestone_escrow_funding(p_escrow_id uuid,p_amount_minor bigint,p_provider text,p_external_ref text)
returns public.escrow_transactions
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_e public.escrow_transactions%rowtype;
  v_c public.freelance_contracts%rowtype;
begin
  if p_amount_minor<=0 then raise exception 'funding amount must be positive'; end if;
  select * into v_e from public.escrow_transactions where id=p_escrow_id for update;
  if not found or v_e.transaction_type<>'funding' or v_e.milestone_id is null then raise exception 'milestone funding escrow not found'; end if;
  if v_e.status not in ('pending_funding','funding_pending','failed','held') then raise exception 'escrow cannot be funded from status %',v_e.status; end if;
  if v_e.amount_minor<>p_amount_minor then raise exception 'funding amount must exactly match milestone escrow'; end if;
  select * into v_c from public.freelance_contracts where id=v_e.contract_id;
  if not found or v_c.status<>'active' then raise exception 'active contract not found'; end if;
  if v_e.status<>'held' then
    update public.escrow_transactions
    set status='held',provider=p_provider,external_ref=p_external_ref,funded_at=coalesce(funded_at,now()),updated_at=now()
    where id=p_escrow_id returning * into v_e;
  end if;
  return v_e;
end;
$function$;
revoke all on function public.record_milestone_escrow_funding(uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.record_milestone_escrow_funding(uuid,bigint,text,text) to service_role;

create or replace function private.review_task_milestone(p_milestone_id uuid,p_decision text,p_notes text default null::text)
returns public.task_milestones
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_m public.task_milestones%rowtype;
  v_c public.freelance_contracts%rowtype;
  v_e public.escrow_transactions%rowtype;
  v_ref text;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'decision must be approved or rejected'; end if;
  select * into v_m from public.task_milestones where id=p_milestone_id for update;
  if not found or v_m.status<>'submitted' then raise exception 'submitted milestone required'; end if;
  select * into v_c from public.freelance_contracts where id=v_m.contract_id;
  if not private.has_employer_access(v_c.employer_id,true) then raise exception 'not authorized'; end if;

  if p_decision='approved' then
    select * into v_e from public.escrow_transactions
    where milestone_id=v_m.id and transaction_type='funding' and status='held'
    limit 1 for update;
    if not found then raise exception 'this milestone escrow must be funded before approval'; end if;
  end if;

  update public.task_milestones
  set status=p_decision,
      approved_at=case when p_decision='approved' then now() else null end,
      reviewed_by=v_uid,
      review_notes=nullif(trim(coalesce(p_notes,'')),''),
      updated_at=now()
  where id=p_milestone_id returning * into v_m;

  if p_decision='approved' then
    v_ref:='mela_payout_'||replace(gen_random_uuid()::text,'-','');
    insert into public.payout_requests(milestone_id,escrow_id,freelancer_id,amount_minor,currency,provider,payout_ref,status)
    values(v_m.id,v_e.id,v_c.freelancer_id,v_e.amount_minor,v_e.currency,'chapa',v_ref,'pending')
    on conflict do nothing;
  end if;

  insert into public.notifications(user_id,title,body,ref_table,ref_id)
  values(v_c.freelancer_id,'Milestone review','Your milestone was '||p_decision||'.','task_milestones',v_m.id);
  return v_m;
end;
$function$;
;

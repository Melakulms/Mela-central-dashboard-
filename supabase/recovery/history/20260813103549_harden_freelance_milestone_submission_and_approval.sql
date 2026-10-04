-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813103549
create or replace function private.submit_task_milestone(p_milestone_id uuid)
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
  select * into v_m from public.task_milestones where id=p_milestone_id for update;
  if not found then raise exception 'milestone not found'; end if;
  select * into v_c from public.freelance_contracts where id=v_m.contract_id;
  if v_c.freelancer_id<>v_uid or v_c.status<>'active' then raise exception 'not authorized or contract inactive'; end if;
  if v_m.status not in ('pending','in_progress','rejected') then raise exception 'milestone cannot be submitted now'; end if;
  if nullif(trim(coalesce(v_m.deliverable_url,'')),'') is null then raise exception 'deliverable_url is required to submit a milestone'; end if;
  update public.task_milestones set status='submitted',submitted_at=now(),updated_at=now() where id=p_milestone_id returning * into v_m;
  perform private.notify_employer_owner(v_c.employer_id,'Milestone submitted','A freelancer submitted a milestone for review.','task_milestones',v_m.id);
  return v_m;
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
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'decision must be approved or rejected'; end if;
  select * into v_m from public.task_milestones where id=p_milestone_id for update;
  if not found or v_m.status<>'submitted' then raise exception 'submitted milestone required'; end if;
  select * into v_c from public.freelance_contracts where id=v_m.contract_id;
  if not private.has_employer_access(v_c.employer_id,true) then raise exception 'not authorized'; end if;
  if p_decision='approved' and v_c.funding_status not in ('held','partially_released') then raise exception 'contract escrow must be funded before milestone approval'; end if;

  if p_decision='approved' then
    insert into public.escrow_transactions(task_id,user_id,amount_coins,status,contract_id,milestone_id,amount_minor,currency,transaction_type,payer_employer_id,updated_at)
    values(v_c.task_id,v_c.freelancer_id,0,'release_pending',v_c.id,v_m.id,round(v_m.amount*100)::bigint,v_c.currency,'release',v_c.employer_id,now())
    on conflict (milestone_id) where transaction_type='release' and milestone_id is not null do update
      set amount_minor=excluded.amount_minor,currency=excluded.currency,status='release_pending',payer_employer_id=excluded.payer_employer_id,updated_at=now();
  end if;

  update public.task_milestones
  set status=p_decision,
      approved_at=case when p_decision='approved' then now() else null end,
      reviewed_by=v_uid,
      review_notes=nullif(trim(coalesce(p_notes,'')),''),
      updated_at=now()
  where id=p_milestone_id returning * into v_m;

  insert into public.notifications(user_id,title,body,ref_table,ref_id)
  values(v_c.freelancer_id,'Milestone review','Your milestone was '||p_decision||'.','task_milestones',v_m.id);
  return v_m;
end;
$function$;
;

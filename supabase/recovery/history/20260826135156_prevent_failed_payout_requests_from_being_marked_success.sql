-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826135156
CREATE OR REPLACE FUNCTION public.record_milestone_payout(p_milestone_id uuid, p_provider text, p_external_ref text)
RETURNS public.task_milestones
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  v_m public.task_milestones%rowtype;
  v_c public.freelance_contracts%rowtype;
  v_e public.escrow_transactions%rowtype;
  v_existing_ref text;
begin
  if nullif(trim(coalesce(p_external_ref,'')),'') is null then raise exception 'payout external reference required'; end if;
  select * into v_m from public.task_milestones where id=p_milestone_id for update;
  if not found then raise exception 'milestone not found'; end if;
  if v_m.status='paid' then
    select external_ref into v_existing_ref from public.escrow_transactions where milestone_id=v_m.id and transaction_type='funding' and status='released' limit 1;
    if v_existing_ref is null or v_existing_ref=p_external_ref then return v_m; end if;
    raise exception 'milestone already paid with a different payout reference';
  end if;
  if v_m.status<>'approved' then raise exception 'approved milestone required'; end if;
  select * into v_c from public.freelance_contracts where id=v_m.contract_id for update;
  if not found or v_c.status not in ('active','completed') then raise exception 'valid contract required'; end if;
  select * into v_e from public.escrow_transactions where milestone_id=v_m.id and transaction_type='funding' and status='held' limit 1 for update;
  if not found then raise exception 'funded milestone escrow not found'; end if;
  if exists(select 1 from public.escrow_transactions where transaction_type='funding' and status='released' and external_ref=p_external_ref and id<>v_e.id) then raise exception 'payout reference already used'; end if;
  update public.escrow_transactions set status='released',provider=p_provider,external_ref=p_external_ref,payout_ref=p_external_ref,released_at=now(),updated_at=now() where id=v_e.id;
  update public.task_milestones set status='paid',updated_at=now() where id=p_milestone_id returning * into v_m;
  if not exists(select 1 from public.task_milestones m where m.contract_id=v_c.id and m.status<>'paid') then
    update public.freelance_contracts set status='completed',completed_at=coalesce(completed_at,now()),updated_at=now() where id=v_c.id;
    update public.marketplace_tasks set status='completed',updated_at=now() where id=v_c.task_id;
  end if;
  update public.payout_requests set status='success',provider=p_provider,provider_ref=p_external_ref,completed_at=now(),updated_at=now() where milestone_id=p_milestone_id and status in ('pending','queued');
  return v_m;
end;
$function$;
;

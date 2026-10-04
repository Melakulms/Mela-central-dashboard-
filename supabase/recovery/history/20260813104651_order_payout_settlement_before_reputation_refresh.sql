-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813104651
create or replace function public.record_milestone_payout(p_milestone_id uuid,p_provider text,p_external_ref text)
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

  if not exists(select 1 from public.task_milestones m where m.contract_id=v_c.id and m.status<>'paid') then
    update public.freelance_contracts set status='completed',completed_at=now(),updated_at=now() where id=v_c.id;
    update public.marketplace_tasks set status='completed',updated_at=now() where id=v_c.task_id;
  end if;

  update public.payout_requests
  set status='success',provider=p_provider,provider_ref=p_external_ref,completed_at=now(),updated_at=now()
  where milestone_id=p_milestone_id and status in ('pending','queued','failed');

  return v_m;
end;
$function$;
revoke all on function public.record_milestone_payout(uuid,text,text) from public,anon,authenticated;
grant execute on function public.record_milestone_payout(uuid,text,text) to service_role;
;

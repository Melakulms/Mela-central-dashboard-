-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813103745
drop policy if exists mela_gate_payouts on public.escrow_transactions;
drop policy if exists mela_gate_payouts on public.payout_requests;
drop policy if exists mela_gate_payouts on public.payout_accounts;

drop policy if exists mela_gate_earn_work on public.escrow_transactions;
create policy mela_gate_earn_work on public.escrow_transactions as restrictive for all to anon,authenticated using (public.platform_feature_available('earn_work')) with check (public.platform_feature_available('earn_work'));

create policy mela_gate_payouts_insert on public.payout_accounts as restrictive for insert to authenticated with check (public.platform_feature_available('payouts'));
create policy mela_gate_payouts_update on public.payout_accounts as restrictive for update to authenticated using (public.platform_feature_available('payouts')) with check (public.platform_feature_available('payouts'));
create policy mela_gate_payouts_delete on public.payout_accounts as restrictive for delete to authenticated using (public.platform_feature_available('payouts'));

create or replace function private.submit_task_milestone(p_milestone_id uuid,p_deliverable_url text,p_submission_note text default null::text)
returns public.task_milestones
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_m public.task_milestones%rowtype;
  v_c public.freelance_contracts%rowtype;
  v_url text := nullif(trim(coalesce(p_deliverable_url,'')),'');
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if v_url is null then raise exception 'deliverable_url is required'; end if;
  select * into v_m from public.task_milestones where id=p_milestone_id for update;
  if not found then raise exception 'milestone not found'; end if;
  select * into v_c from public.freelance_contracts where id=v_m.contract_id;
  if v_c.freelancer_id<>v_uid or v_c.status<>'active' then raise exception 'not authorized or contract inactive'; end if;
  if v_m.status not in ('pending','in_progress','rejected') then raise exception 'milestone cannot be submitted now'; end if;
  update public.task_milestones
  set deliverable_url=v_url,
      submission_note=nullif(trim(coalesce(p_submission_note,'')),''),
      status='submitted',submitted_at=now(),updated_at=now()
  where id=p_milestone_id returning * into v_m;
  perform private.notify_employer_owner(v_c.employer_id,'Milestone submitted','A freelancer submitted a milestone for review.','task_milestones',v_m.id);
  return v_m;
end;
$function$;

create or replace function public.submit_task_milestone(p_milestone_id uuid,p_deliverable_url text,p_submission_note text default null::text)
returns public.task_milestones
language sql
set search_path to ''
as $function$ select * from private.submit_task_milestone(p_milestone_id,p_deliverable_url,p_submission_note); $function$;

grant execute on function public.submit_task_milestone(uuid,text,text) to authenticated,service_role;
;

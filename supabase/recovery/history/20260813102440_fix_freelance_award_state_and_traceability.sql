-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813102440
create or replace function private.award_freelance_task(p_submission_id uuid, p_agreed_amount numeric, p_terms text default null::text)
returns public.freelance_contracts
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_sub public.marketplace_submissions%rowtype;
  v_task public.marketplace_tasks%rowtype;
  v_contract public.freelance_contracts%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_agreed_amount <= 0 then raise exception 'agreed amount must be positive'; end if;

  select * into v_sub from public.marketplace_submissions where id=p_submission_id for update;
  if not found or v_sub.status not in ('pending','shortlisted') then raise exception 'proposal is not awardable'; end if;

  select * into v_task from public.marketplace_tasks where id=v_sub.task_id for update;
  if not found or v_task.status <> 'open' then raise exception 'task is not open'; end if;
  if not private.has_employer_access(v_task.employer_id,true) then raise exception 'not authorized'; end if;
  if v_task.budget_amount is not null and p_agreed_amount > v_task.budget_amount then raise exception 'agreed amount exceeds task budget'; end if;

  insert into public.freelance_contracts(task_id,employer_id,freelancer_id,agreed_amount,currency,terms,status,created_by,funding_status,submission_id)
  values(v_task.id,v_task.employer_id,v_sub.user_id,p_agreed_amount,v_task.currency,p_terms,'proposed',v_uid,'unfunded',v_sub.id)
  returning * into v_contract;

  update public.marketplace_submissions
  set status='accepted',reviewed_by=v_uid,reviewed_at=now(),updated_at=now()
  where id=v_sub.id;

  update public.marketplace_tasks
  set status='assigned',assigned_to=v_sub.user_id,updated_at=now()
  where id=v_task.id;

  insert into public.notifications(user_id,title,body,ref_table,ref_id)
  values(v_sub.user_id,'Freelance task awarded','You received a proposed Mela freelance contract. Review and accept it to begin.','freelance_contracts',v_contract.id);

  return v_contract;
end;
$function$;
;

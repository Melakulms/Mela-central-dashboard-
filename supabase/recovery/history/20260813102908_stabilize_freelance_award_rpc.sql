-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813102908
create or replace function private.award_freelance_task(p_submission_id uuid, p_agreed_amount numeric, p_terms text default null::text)
returns public.freelance_contracts
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_status text;
  v_task_id uuid;
  v_freelancer_id uuid;
  v_task_status text;
  v_employer_id uuid;
  v_budget numeric;
  v_currency text;
  v_contract public.freelance_contracts%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_agreed_amount <= 0 then raise exception 'agreed amount must be positive'; end if;

  select s.status,s.task_id,s.user_id
    into v_status,v_task_id,v_freelancer_id
  from public.marketplace_submissions s
  where s.id=p_submission_id
  for update;

  if v_status is null then raise exception 'proposal not found'; end if;
  if v_status not in ('pending','shortlisted') then raise exception 'proposal is not awardable: %',v_status; end if;

  select t.status,t.employer_id,t.budget_amount,t.currency
    into v_task_status,v_employer_id,v_budget,v_currency
  from public.marketplace_tasks t
  where t.id=v_task_id
  for update;

  if v_task_status is null then raise exception 'task not found'; end if;
  if v_task_status <> 'open' then raise exception 'task is not open: %',v_task_status; end if;
  if not private.has_employer_access(v_employer_id,true) then raise exception 'not authorized'; end if;
  if v_budget is not null and p_agreed_amount > v_budget then raise exception 'agreed amount exceeds task budget'; end if;

  insert into public.freelance_contracts(task_id,employer_id,freelancer_id,agreed_amount,currency,terms,status,created_by,funding_status,submission_id)
  values(v_task_id,v_employer_id,v_freelancer_id,p_agreed_amount,v_currency,p_terms,'proposed',v_uid,'unfunded',p_submission_id)
  returning * into v_contract;

  update public.marketplace_submissions
  set status='accepted',reviewed_by=v_uid,reviewed_at=now(),updated_at=now()
  where id=p_submission_id;

  update public.marketplace_tasks
  set status='assigned',assigned_to=v_freelancer_id,updated_at=now()
  where id=v_task_id;

  insert into public.notifications(user_id,title,body,ref_table,ref_id)
  values(v_freelancer_id,'Freelance task awarded','You received a proposed Mela freelance contract. Review and accept it to begin.','freelance_contracts',v_contract.id);

  return v_contract;
end;
$function$;
;

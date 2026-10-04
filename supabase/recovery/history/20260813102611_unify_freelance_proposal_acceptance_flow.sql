-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813102611
create or replace function private.process_accepted_marketplace_proposal()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $function$
declare
  v_task public.marketplace_tasks%rowtype;
  v_contract uuid;
  v_amount numeric;
  v_uid uuid := (select auth.uid());
begin
  if new.status <> 'accepted' or old.status = 'accepted' then return new; end if;

  -- The canonical award RPC creates the proposed contract before it marks the
  -- proposal accepted. In that path, do not create a second contract.
  select id into v_contract
  from public.freelance_contracts
  where submission_id=new.id
     or (task_id=new.task_id and freelancer_id=new.user_id)
  order by created_at desc
  limit 1;

  if v_contract is not null then
    return new;
  end if;

  select * into v_task from public.marketplace_tasks where id=new.task_id for update;
  if not found or v_task.status <> 'open' or v_task.assigned_to is not null then
    raise exception 'task is no longer available';
  end if;

  v_amount := coalesce(new.proposed_amount,new.bid_amount,v_task.budget_amount);
  if v_amount is null or v_amount <= 0 then raise exception 'accepted proposal requires a positive budget'; end if;
  if coalesce(new.currency,v_task.currency) <> v_task.currency then raise exception 'proposal currency must match task currency'; end if;

  perform set_config('mela.system_workflow','on',true);

  update public.marketplace_tasks
  set assigned_to=new.user_id,status='assigned',updated_at=now()
  where id=v_task.id;

  insert into public.freelance_contracts(
    task_id,submission_id,employer_id,freelancer_id,agreed_amount,currency,terms,
    status,created_by,funding_status
  ) values (
    v_task.id,new.id,v_task.employer_id,new.user_id,v_amount,v_task.currency,
    'Accepted Mela marketplace proposal','proposed',coalesce(v_uid,v_task.posted_by),'unfunded'
  ) returning id into v_contract;

  update public.marketplace_submissions
  set status='rejected',reviewed_at=now(),reviewed_by=coalesce(new.reviewed_by,v_uid),updated_at=now()
  where task_id=v_task.id and id<>new.id and status='pending';

  perform private.create_notification(new.user_id,'Freelance proposal accepted','Your proposal was accepted. Review and accept the Mela contract to begin.','freelance_contracts',v_contract);
  perform private.create_notification(v_task.posted_by,'Freelance contract proposed','The selected freelancer must accept the contract before escrow funding.','freelance_contracts',v_contract);
  return new;
end;
$function$;
;

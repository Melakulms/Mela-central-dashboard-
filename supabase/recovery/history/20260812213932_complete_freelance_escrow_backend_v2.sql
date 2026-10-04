-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812213932
-- Production freelance marketplace, contract, milestone and escrow state machines.

alter table public.marketplace_tasks add column if not exists updated_at timestamptz not null default now();
alter table public.marketplace_tasks drop constraint if exists marketplace_task_status_chk;
alter table public.marketplace_tasks add constraint marketplace_task_status_chk check (status in ('draft','open','paused','awarded','in_progress','completed','cancelled'));
alter table public.marketplace_tasks drop constraint if exists marketplace_task_budget_chk;
alter table public.marketplace_tasks add constraint marketplace_task_budget_chk check (budget_amount is null or budget_amount>=0);
create index if not exists marketplace_tasks_employer_status_idx on public.marketplace_tasks(employer_id,status);
create index if not exists marketplace_tasks_open_deadline_idx on public.marketplace_tasks(status,deadline);

create or replace function private.prepare_marketplace_task()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_company public.employers%rowtype; v_trusted boolean := current_user in ('postgres','service_role');
begin
  new.updated_at:=now();
  if new.posted_by is null then new.posted_by:=(select auth.uid()); end if;
  if new.employer_id is null then raise exception 'employer_id is required'; end if;
  select * into v_company from public.employers where id=new.employer_id;
  if not found then raise exception 'employer not found'; end if;
  if not v_trusted and (select auth.uid()) is not null then
    if tg_op='UPDATE' and (new.employer_id is distinct from old.employer_id or new.posted_by is distinct from old.posted_by or new.assigned_to is distinct from old.assigned_to) then raise exception 'task ownership and assignment are system managed'; end if;
    if new.status in ('awarded','in_progress','completed') and (tg_op='INSERT' or new.status is distinct from old.status) then raise exception 'this task status is system managed'; end if;
    if tg_op='UPDATE' and old.status in ('awarded','in_progress','completed') and new.status is distinct from old.status then raise exception 'system-managed task status cannot be edited directly'; end if;
  end if;
  if new.status='open' then
    if not (v_company.verified=true and v_company.verification_status='verified') then raise exception 'employer must be verified before opening freelance tasks'; end if;
    if new.deadline is not null and new.deadline<=now() then raise exception 'deadline must be in the future'; end if;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_prepare_marketplace_task on public.marketplace_tasks;
create trigger trg_prepare_marketplace_task before insert or update on public.marketplace_tasks for each row execute function private.prepare_marketplace_task();

drop policy if exists "marketplace: poster manage" on public.marketplace_tasks;
drop policy if exists "Marketplace tasks public read" on public.marketplace_tasks;
drop policy if exists "Marketplace tasks authenticated read" on public.marketplace_tasks;
drop policy if exists "Employer teams create marketplace tasks" on public.marketplace_tasks;
drop policy if exists "Employer teams update marketplace tasks" on public.marketplace_tasks;
drop policy if exists "Employer teams delete draft marketplace tasks" on public.marketplace_tasks;
create policy "Marketplace tasks public read" on public.marketplace_tasks for select to anon
using (status='open' and (deadline is null or deadline>now()) and exists(select 1 from public.employers e where e.id=employer_id and e.verified=true and e.verification_status='verified'));
create policy "Marketplace tasks authenticated read" on public.marketplace_tasks for select to authenticated
using ((status='open' and (deadline is null or deadline>now()) and exists(select 1 from public.employers e where e.id=employer_id and e.verified=true and e.verification_status='verified')) or assigned_to=(select auth.uid()) or private.has_employer_access(employer_id,false) or private.is_admin_user());
create policy "Employer teams create marketplace tasks" on public.marketplace_tasks for insert to authenticated
with check (posted_by=(select auth.uid()) and private.has_employer_access(employer_id,true));
create policy "Employer teams update marketplace tasks" on public.marketplace_tasks for update to authenticated
using (private.has_employer_access(employer_id,true)) with check (private.has_employer_access(employer_id,true));
create policy "Employer teams delete draft marketplace tasks" on public.marketplace_tasks for delete to authenticated
using (status='draft' and private.has_employer_access(employer_id,true));
revoke update on public.marketplace_tasks from authenticated;
grant update (title,description,task_type,reward_coins,budget_amount,currency,deadline,status,skills_required) on public.marketplace_tasks to authenticated;

alter table public.marketplace_submissions add column if not exists proposal_text text;
alter table public.marketplace_submissions add column if not exists proposed_amount numeric;
alter table public.marketplace_submissions add column if not exists estimated_days integer;
alter table public.marketplace_submissions add column if not exists reviewed_at timestamptz;
alter table public.marketplace_submissions add column if not exists reviewed_by uuid references public.profiles(id) on delete set null;
alter table public.marketplace_submissions add column if not exists withdrawn_at timestamptz;
alter table public.marketplace_submissions add column if not exists updated_at timestamptz not null default now();
alter table public.marketplace_submissions drop constraint if exists marketplace_submission_status_chk;
alter table public.marketplace_submissions add constraint marketplace_submission_status_chk check (status in ('pending','shortlisted','accepted','rejected','withdrawn'));
alter table public.marketplace_submissions drop constraint if exists marketplace_submission_amount_chk;
alter table public.marketplace_submissions add constraint marketplace_submission_amount_chk check (proposed_amount is null or proposed_amount>=0);
alter table public.marketplace_submissions drop constraint if exists marketplace_submission_days_chk;
alter table public.marketplace_submissions add constraint marketplace_submission_days_chk check (estimated_days is null or estimated_days between 1 and 365);
create unique index if not exists marketplace_submission_task_user_unique on public.marketplace_submissions(task_id,user_id);
create or replace function private.prepare_marketplace_submission()
returns trigger language plpgsql security definer set search_path=''
as $$ begin if tg_op='INSERT' then new.status:='pending'; new.submitted_at:=now(); new.reviewed_at:=null; new.reviewed_by:=null; new.withdrawn_at:=null; end if; new.updated_at:=now(); return new; end; $$;
drop trigger if exists trg_prepare_marketplace_submission on public.marketplace_submissions;
create trigger trg_prepare_marketplace_submission before insert or update on public.marketplace_submissions for each row execute function private.prepare_marketplace_submission();

drop policy if exists "marketplace_submissions: self manage" on public.marketplace_submissions;
drop policy if exists "Marketplace submissions readable by participants" on public.marketplace_submissions;
drop policy if exists "Students submit freelance proposals" on public.marketplace_submissions;
create policy "Marketplace submissions readable by participants" on public.marketplace_submissions for select to authenticated
using (user_id=(select auth.uid()) or private.is_admin_user() or exists(select 1 from public.marketplace_tasks t where t.id=task_id and private.has_employer_access(t.employer_id,false)));
create policy "Students submit freelance proposals" on public.marketplace_submissions for insert to authenticated
with check (user_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='student'::public.user_role) and exists(select 1 from public.marketplace_tasks t where t.id=task_id and t.status='open' and (t.deadline is null or t.deadline>now())));
revoke update, delete on public.marketplace_submissions from authenticated;
revoke insert on public.marketplace_submissions from authenticated;
grant insert (task_id,user_id,content_url,proposal_text,proposed_amount,estimated_days) on public.marketplace_submissions to authenticated;

alter table public.freelance_contracts add column if not exists created_by uuid references public.profiles(id) on delete set null;
alter table public.freelance_contracts add column if not exists accepted_at timestamptz;
alter table public.freelance_contracts add column if not exists updated_at timestamptz not null default now();
alter table public.freelance_contracts add column if not exists cancelled_at timestamptz;
alter table public.freelance_contracts add column if not exists cancellation_reason text;
alter table public.freelance_contracts add column if not exists funding_status text not null default 'unfunded';
alter table public.freelance_contracts add column if not exists funded_amount numeric not null default 0;
alter table public.freelance_contracts add column if not exists released_amount numeric not null default 0;
alter table public.freelance_contracts alter column status set default 'proposed';
alter table public.freelance_contracts drop constraint if exists freelance_contract_status_chk;
alter table public.freelance_contracts add constraint freelance_contract_status_chk check (status in ('proposed','active','completed','cancelled','disputed'));
alter table public.freelance_contracts drop constraint if exists freelance_contract_amount_chk;
alter table public.freelance_contracts add constraint freelance_contract_amount_chk check (agreed_amount>0);
alter table public.freelance_contracts drop constraint if exists freelance_contract_funding_status_chk;
alter table public.freelance_contracts add constraint freelance_contract_funding_status_chk check (funding_status in ('unfunded','pending','held','partially_released','released','refund_pending','refunded','disputed'));
alter table public.freelance_contracts drop constraint if exists freelance_contract_funding_amounts_chk;
alter table public.freelance_contracts add constraint freelance_contract_funding_amounts_chk check (funded_amount>=0 and released_amount>=0 and released_amount<=funded_amount);
create index if not exists freelance_contracts_employer_status_idx on public.freelance_contracts(employer_id,status);
create index if not exists freelance_contracts_freelancer_status_idx on public.freelance_contracts(freelancer_id,status);

alter table public.task_milestones add column if not exists review_notes text;
alter table public.task_milestones add column if not exists reviewed_by uuid references public.profiles(id) on delete set null;
alter table public.task_milestones add column if not exists updated_at timestamptz not null default now();
alter table public.task_milestones drop constraint if exists milestone_amount_chk;
alter table public.task_milestones add constraint milestone_amount_chk check (amount>0);

alter table public.escrow_transactions add column if not exists milestone_id uuid references public.task_milestones(id) on delete set null;
alter table public.escrow_transactions add column if not exists transaction_type text not null default 'funding';
alter table public.escrow_transactions add column if not exists payer_employer_id uuid references public.employers(id) on delete set null;
alter table public.escrow_transactions add column if not exists updated_at timestamptz not null default now();
alter table public.escrow_transactions alter column amount_coins set default 0;
alter table public.escrow_transactions drop constraint if exists escrow_status_chk;
alter table public.escrow_transactions add constraint escrow_status_chk check (status in ('funding_pending','held','awaiting_funding','release_pending','released','refund_pending','refunded','disputed','failed','cancelled'));
alter table public.escrow_transactions drop constraint if exists escrow_transaction_type_chk;
alter table public.escrow_transactions add constraint escrow_transaction_type_chk check (transaction_type in ('funding','release','refund'));
alter table public.escrow_transactions drop constraint if exists escrow_amount_minor_chk;
alter table public.escrow_transactions add constraint escrow_amount_minor_chk check (amount_minor is null or amount_minor>=0);
create unique index if not exists escrow_one_funding_per_contract on public.escrow_transactions(contract_id) where transaction_type='funding' and contract_id is not null;
create unique index if not exists escrow_one_release_per_milestone on public.escrow_transactions(milestone_id) where transaction_type='release' and milestone_id is not null;

drop policy if exists "Employer teams create contracts" on public.freelance_contracts;
drop policy if exists "Employer teams update contracts" on public.freelance_contracts;
drop policy if exists "Employer teams delete contracts" on public.freelance_contracts;
revoke insert, update, delete on public.freelance_contracts from authenticated;
grant select on public.freelance_contracts to authenticated;
drop policy if exists "Employer teams insert milestones" on public.task_milestones;
drop policy if exists "Employer teams update milestones" on public.task_milestones;
drop policy if exists "Employer teams delete milestones" on public.task_milestones;
revoke insert, update, delete on public.task_milestones from authenticated;
grant select on public.task_milestones to authenticated;
drop policy if exists "escrow: self read" on public.escrow_transactions;
drop policy if exists "Escrow readable by participants" on public.escrow_transactions;
create policy "Escrow readable by participants" on public.escrow_transactions for select to authenticated
using (private.is_admin_user() or user_id=(select auth.uid()) or (payer_employer_id is not null and private.has_employer_access(payer_employer_id,false)) or exists(select 1 from public.freelance_contracts c where c.id=contract_id and (c.freelancer_id=(select auth.uid()) or (c.employer_id is not null and private.has_employer_access(c.employer_id,false)))));
revoke insert, update, delete on public.escrow_transactions from authenticated;
grant select on public.escrow_transactions to authenticated;
revoke update, delete on public.task_messages from authenticated;

create or replace function private.notify_employer_owner(p_employer_id uuid,p_title text,p_body text,p_ref_table text,p_ref_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ declare v_owner uuid; begin select owner_id into v_owner from public.employers where id=p_employer_id; if v_owner is not null then insert into public.notifications(user_id,title,body,ref_table,ref_id) values(v_owner,p_title,p_body,p_ref_table,p_ref_id); end if; end; $$;
revoke all on function private.notify_employer_owner(uuid,text,text,text,uuid) from public, anon, authenticated;
grant execute on function private.notify_employer_owner(uuid,text,text,text,uuid) to service_role;

create or replace function public.withdraw_freelance_proposal(p_submission_id uuid)
returns public.marketplace_submissions language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_row public.marketplace_submissions%rowtype; begin if v_uid is null then raise exception 'authentication required'; end if; select * into v_row from public.marketplace_submissions where id=p_submission_id for update; if not found then raise exception 'proposal not found'; end if; if v_row.user_id<>v_uid then raise exception 'not authorized'; end if; if v_row.status not in ('pending','shortlisted') then raise exception 'proposal cannot be withdrawn now'; end if; update public.marketplace_submissions set status='withdrawn',withdrawn_at=now(),updated_at=now() where id=p_submission_id returning * into v_row; return v_row; end; $$;

create or replace function public.shortlist_freelance_proposal(p_submission_id uuid)
returns public.marketplace_submissions language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_row public.marketplace_submissions%rowtype; v_employer uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_row from public.marketplace_submissions where id=p_submission_id for update;
  if not found then raise exception 'proposal not found'; end if;
  select employer_id into v_employer from public.marketplace_tasks where id=v_row.task_id;
  if not private.has_employer_access(v_employer,true) then raise exception 'not authorized'; end if;
  if v_row.status<>'pending' then raise exception 'only pending proposals can be shortlisted'; end if;
  update public.marketplace_submissions set status='shortlisted',reviewed_by=v_uid,reviewed_at=now(),updated_at=now() where id=p_submission_id returning * into v_row;
  insert into public.notifications(user_id,title,body,ref_table,ref_id) values(v_row.user_id,'Freelance proposal shortlisted','Your proposal was shortlisted.','marketplace_submissions',v_row.id);
  return v_row;
end;
$$;

create or replace function public.award_freelance_task(p_submission_id uuid,p_agreed_amount numeric,p_terms text default null)
returns public.freelance_contracts language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_sub public.marketplace_submissions%rowtype; v_task public.marketplace_tasks%rowtype; v_contract public.freelance_contracts%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_agreed_amount<=0 then raise exception 'agreed amount must be positive'; end if;
  select * into v_sub from public.marketplace_submissions where id=p_submission_id for update;
  if not found or v_sub.status not in ('pending','shortlisted') then raise exception 'proposal is not awardable'; end if;
  select * into v_task from public.marketplace_tasks where id=v_sub.task_id for update;
  if not found or v_task.status<>'open' then raise exception 'task is not open'; end if;
  if not private.has_employer_access(v_task.employer_id,true) then raise exception 'not authorized'; end if;
  if v_task.budget_amount is not null and p_agreed_amount>v_task.budget_amount then raise exception 'agreed amount exceeds task budget'; end if;
  insert into public.freelance_contracts(task_id,employer_id,freelancer_id,agreed_amount,currency,terms,status,created_by,funding_status)
  values(v_task.id,v_task.employer_id,v_sub.user_id,p_agreed_amount,v_task.currency,p_terms,'proposed',v_uid,'unfunded') returning * into v_contract;
  update public.marketplace_submissions set status='accepted',reviewed_by=v_uid,reviewed_at=now(),updated_at=now() where id=v_sub.id;
  update public.marketplace_tasks set status='awarded',assigned_to=v_sub.user_id,updated_at=now() where id=v_task.id;
  insert into public.notifications(user_id,title,body,ref_table,ref_id) values(v_sub.user_id,'Freelance task awarded','You received a proposed Mela freelance contract. Review and accept it to begin.','freelance_contracts',v_contract.id);
  return v_contract;
end;
$$;

create or replace function public.respond_freelance_contract(p_contract_id uuid,p_accept boolean,p_reason text default null)
returns public.freelance_contracts language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_c public.freelance_contracts%rowtype; v_minor bigint;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_c from public.freelance_contracts where id=p_contract_id for update;
  if not found then raise exception 'contract not found'; end if;
  if v_c.freelancer_id<>v_uid then raise exception 'only the selected freelancer can respond'; end if;
  if v_c.status<>'proposed' then raise exception 'contract is no longer awaiting response'; end if;
  if p_accept then
    update public.freelance_contracts set status='active',accepted_at=now(),started_at=now(),updated_at=now(),funding_status='pending' where id=p_contract_id returning * into v_c;
    update public.marketplace_tasks set status='in_progress',assigned_to=v_uid,updated_at=now() where id=v_c.task_id;
    v_minor:=round(v_c.agreed_amount*100)::bigint;
    insert into public.escrow_transactions(task_id,user_id,amount_coins,status,contract_id,amount_minor,currency,transaction_type,payer_employer_id)
    values(v_c.task_id,v_c.freelancer_id,0,'funding_pending',v_c.id,v_minor,v_c.currency,'funding',v_c.employer_id)
    on conflict (contract_id) where transaction_type='funding' and contract_id is not null do nothing;
    perform private.notify_employer_owner(v_c.employer_id,'Freelance contract accepted','The selected freelancer accepted the contract. Escrow funding is now required.','freelance_contracts',v_c.id);
  else
    update public.freelance_contracts set status='cancelled',cancelled_at=now(),cancellation_reason=coalesce(nullif(trim(coalesce(p_reason,'')),''),'declined_by_freelancer'),updated_at=now() where id=p_contract_id returning * into v_c;
    update public.marketplace_tasks set status='open',assigned_to=null,updated_at=now() where id=v_c.task_id;
    update public.marketplace_submissions set status='rejected',reviewed_at=now(),updated_at=now() where task_id=v_c.task_id and user_id=v_c.freelancer_id;
    perform private.notify_employer_owner(v_c.employer_id,'Freelance contract declined','The selected freelancer declined the proposed contract. The task was reopened.','freelance_contracts',v_c.id);
  end if;
  return v_c;
end;
$$;

create or replace function public.create_task_milestone(p_contract_id uuid,p_title text,p_amount numeric,p_due_at timestamptz default null,p_description text default null)
returns public.task_milestones language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_c public.freelance_contracts%rowtype; v_sum numeric; v_order integer; v_row public.task_milestones%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if nullif(trim(coalesce(p_title,'')),'') is null then raise exception 'title is required'; end if;
  if p_amount<=0 then raise exception 'milestone amount must be positive'; end if;
  select * into v_c from public.freelance_contracts where id=p_contract_id for update;
  if not found or v_c.status not in ('proposed','active') then raise exception 'contract does not accept milestones'; end if;
  if not private.has_employer_access(v_c.employer_id,true) then raise exception 'not authorized'; end if;
  select coalesce(sum(amount),0),coalesce(max(milestone_order),0)+1 into v_sum,v_order from public.task_milestones where contract_id=p_contract_id;
  if v_sum+p_amount>v_c.agreed_amount then raise exception 'milestone total exceeds agreed contract amount'; end if;
  insert into public.task_milestones(contract_id,milestone_order,title,description,amount,due_at,status,updated_at)
  values(p_contract_id,v_order,trim(p_title),p_description,p_amount,p_due_at,'pending',now()) returning * into v_row;
  insert into public.notifications(user_id,title,body,ref_table,ref_id) values(v_c.freelancer_id,'New freelance milestone','A milestone was added to your Mela freelance contract.','task_milestones',v_row.id);
  return v_row;
end;
$$;

create or replace function public.submit_task_milestone(p_milestone_id uuid)
returns public.task_milestones language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_m public.task_milestones%rowtype; v_c public.freelance_contracts%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_m from public.task_milestones where id=p_milestone_id for update;
  if not found then raise exception 'milestone not found'; end if;
  select * into v_c from public.freelance_contracts where id=v_m.contract_id;
  if v_c.freelancer_id<>v_uid or v_c.status<>'active' then raise exception 'not authorized or contract inactive'; end if;
  if v_m.status not in ('pending','in_progress','rejected') then raise exception 'milestone cannot be submitted now'; end if;
  update public.task_milestones set status='submitted',submitted_at=now(),updated_at=now() where id=p_milestone_id returning * into v_m;
  perform private.notify_employer_owner(v_c.employer_id,'Milestone submitted','A freelancer submitted a milestone for review.','task_milestones',v_m.id);
  return v_m;
end;
$$;

create or replace function public.review_task_milestone(p_milestone_id uuid,p_decision text,p_notes text default null)
returns public.task_milestones language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_m public.task_milestones%rowtype; v_c public.freelance_contracts%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'decision must be approved or rejected'; end if;
  select * into v_m from public.task_milestones where id=p_milestone_id for update;
  if not found or v_m.status<>'submitted' then raise exception 'submitted milestone required'; end if;
  select * into v_c from public.freelance_contracts where id=v_m.contract_id;
  if not private.has_employer_access(v_c.employer_id,true) then raise exception 'not authorized'; end if;
  update public.task_milestones set status=p_decision,approved_at=case when p_decision='approved' then now() else null end,reviewed_by=v_uid,review_notes=nullif(trim(coalesce(p_notes,'')),''),updated_at=now() where id=p_milestone_id returning * into v_m;
  if p_decision='approved' then
    insert into public.escrow_transactions(task_id,user_id,amount_coins,status,contract_id,milestone_id,amount_minor,currency,transaction_type,payer_employer_id)
    values(v_c.task_id,v_c.freelancer_id,0,case when v_c.funding_status='held' then 'release_pending' else 'awaiting_funding' end,v_c.id,v_m.id,round(v_m.amount*100)::bigint,v_c.currency,'release',v_c.employer_id)
    on conflict (milestone_id) where transaction_type='release' and milestone_id is not null do update set status=excluded.status,updated_at=now();
  end if;
  insert into public.notifications(user_id,title,body,ref_table,ref_id) values(v_c.freelancer_id,'Milestone review','Your milestone was '||p_decision||'.','task_milestones',v_m.id);
  return v_m;
end;
$$;

create or replace function public.raise_contract_dispute(p_contract_id uuid,p_reason text)
returns public.freelance_contracts language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_c public.freelance_contracts%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'reason is required'; end if;
  select * into v_c from public.freelance_contracts where id=p_contract_id for update;
  if not found or v_c.status not in ('active','disputed') then raise exception 'active contract required'; end if;
  if v_uid<>v_c.freelancer_id and not private.has_employer_access(v_c.employer_id,false) and not private.is_admin_user() then raise exception 'not authorized'; end if;
  update public.freelance_contracts set status='disputed',funding_status='disputed',updated_at=now() where id=p_contract_id returning * into v_c;
  update public.escrow_transactions set status='disputed',updated_at=now() where contract_id=p_contract_id and status not in ('released','refunded','cancelled');
  insert into public.reports(reporter_id,target_type,target_id,reason,details,status) values(v_uid,'freelance_contract',p_contract_id,'contract_dispute',trim(p_reason),'open');
  return v_c;
end;
$$;

create or replace function public.cancel_freelance_contract(p_contract_id uuid,p_reason text default null)
returns public.freelance_contracts language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_c public.freelance_contracts%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_c from public.freelance_contracts where id=p_contract_id for update;
  if not found then raise exception 'contract not found'; end if;
  if v_uid<>v_c.freelancer_id and not private.has_employer_access(v_c.employer_id,true) and not private.is_admin_user() then raise exception 'not authorized'; end if;
  if v_c.status='active' and v_c.funding_status in ('held','partially_released','released') and not private.is_admin_user() then raise exception 'funded contracts must use dispute/refund workflow'; end if;
  if v_c.status not in ('proposed','active') then raise exception 'contract cannot be cancelled now'; end if;
  update public.freelance_contracts set status='cancelled',cancelled_at=now(),cancellation_reason=nullif(trim(coalesce(p_reason,'')),''),updated_at=now() where id=p_contract_id returning * into v_c;
  update public.marketplace_tasks set status='open',assigned_to=null,updated_at=now() where id=v_c.task_id;
  update public.escrow_transactions set status='cancelled',updated_at=now() where contract_id=p_contract_id and status in ('funding_pending','awaiting_funding');
  return v_c;
end;
$$;

create or replace function public.record_escrow_funding(p_contract_id uuid,p_amount_minor bigint,p_provider text,p_external_ref text)
returns public.freelance_contracts language plpgsql security definer set search_path=''
as $$
declare v_c public.freelance_contracts%rowtype; v_amount numeric;
begin
  if p_amount_minor<=0 then raise exception 'funding amount must be positive'; end if;
  select * into v_c from public.freelance_contracts where id=p_contract_id for update;
  if not found or v_c.status<>'active' then raise exception 'active contract not found'; end if;
  v_amount:=p_amount_minor::numeric/100;
  if v_amount<v_c.agreed_amount then raise exception 'funding amount is below agreed contract amount'; end if;
  update public.freelance_contracts set funded_amount=v_amount,funding_status=case when released_amount>0 then 'partially_released' else 'held' end,updated_at=now() where id=p_contract_id returning * into v_c;
  update public.escrow_transactions set status='held',provider=p_provider,external_ref=p_external_ref,amount_minor=p_amount_minor,updated_at=now() where contract_id=p_contract_id and transaction_type='funding';
  update public.escrow_transactions set status='release_pending',updated_at=now() where contract_id=p_contract_id and transaction_type='release' and status='awaiting_funding';
  return v_c;
end;
$$;

create or replace function public.record_milestone_payout(p_milestone_id uuid,p_provider text,p_external_ref text)
returns public.task_milestones language plpgsql security definer set search_path=''
as $$
declare v_m public.task_milestones%rowtype; v_c public.freelance_contracts%rowtype; v_tx public.escrow_transactions%rowtype; v_new_released numeric;
begin
  select * into v_m from public.task_milestones where id=p_milestone_id for update;
  if not found or v_m.status<>'approved' then raise exception 'approved milestone required'; end if;
  select * into v_c from public.freelance_contracts where id=v_m.contract_id for update;
  if v_c.funding_status not in ('held','partially_released') then raise exception 'contract escrow is not funded'; end if;
  select * into v_tx from public.escrow_transactions where milestone_id=p_milestone_id and transaction_type='release' for update;
  if not found then raise exception 'release transaction not found'; end if;
  if v_tx.status='released' then return v_m; end if;
  if v_tx.status<>'release_pending' then raise exception 'release is not pending'; end if;
  update public.escrow_transactions set status='released',provider=p_provider,external_ref=p_external_ref,released_at=now(),updated_at=now() where id=v_tx.id;
  update public.task_milestones set status='paid',updated_at=now() where id=p_milestone_id returning * into v_m;
  v_new_released:=v_c.released_amount+v_m.amount;
  update public.freelance_contracts set released_amount=v_new_released,funding_status=case when v_new_released>=agreed_amount then 'released' else 'partially_released' end,status=case when v_new_released>=agreed_amount then 'completed' else status end,completed_at=case when v_new_released>=agreed_amount then now() else completed_at end,updated_at=now() where id=v_c.id returning * into v_c;
  if v_c.status='completed' then update public.marketplace_tasks set status='completed',updated_at=now() where id=v_c.task_id; end if;
  insert into public.notifications(user_id,title,body,ref_table,ref_id) values(v_c.freelancer_id,'Milestone payment released','A milestone payment was released from escrow.','task_milestones',v_m.id);
  return v_m;
end;
$$;

revoke all on function public.withdraw_freelance_proposal(uuid) from public, anon;
revoke all on function public.shortlist_freelance_proposal(uuid) from public, anon;
revoke all on function public.award_freelance_task(uuid,numeric,text) from public, anon;
revoke all on function public.respond_freelance_contract(uuid,boolean,text) from public, anon;
revoke all on function public.create_task_milestone(uuid,text,numeric,timestamptz,text) from public, anon;
revoke all on function public.submit_task_milestone(uuid) from public, anon;
revoke all on function public.review_task_milestone(uuid,text,text) from public, anon;
revoke all on function public.raise_contract_dispute(uuid,text) from public, anon;
revoke all on function public.cancel_freelance_contract(uuid,text) from public, anon;
revoke all on function public.record_escrow_funding(uuid,bigint,text,text) from public, anon, authenticated;
revoke all on function public.record_milestone_payout(uuid,text,text) from public, anon, authenticated;
grant execute on function public.withdraw_freelance_proposal(uuid) to authenticated, service_role;
grant execute on function public.shortlist_freelance_proposal(uuid) to authenticated, service_role;
grant execute on function public.award_freelance_task(uuid,numeric,text) to authenticated, service_role;
grant execute on function public.respond_freelance_contract(uuid,boolean,text) to authenticated, service_role;
grant execute on function public.create_task_milestone(uuid,text,numeric,timestamptz,text) to authenticated, service_role;
grant execute on function public.submit_task_milestone(uuid) to authenticated, service_role;
grant execute on function public.review_task_milestone(uuid,text,text) to authenticated, service_role;
grant execute on function public.raise_contract_dispute(uuid,text) to authenticated, service_role;
grant execute on function public.cancel_freelance_contract(uuid,text) to authenticated, service_role;
grant execute on function public.record_escrow_funding(uuid,bigint,text,text) to service_role;
grant execute on function public.record_milestone_payout(uuid,text,text) to service_role;

;

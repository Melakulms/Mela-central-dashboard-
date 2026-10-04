-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812213831
-- Mela V1 freelance marketplace and escrow workflow.

alter table public.marketplace_tasks add column if not exists updated_at timestamptz not null default now();
alter table public.marketplace_tasks add column if not exists published_at timestamptz;
do $$ begin
  if not exists(select 1 from pg_constraint where conrelid='public.marketplace_tasks'::regclass and conname='marketplace_task_status_chk') then
    alter table public.marketplace_tasks add constraint marketplace_task_status_chk check (status in ('draft','open','assigned','in_progress','completed','cancelled','disputed'));
  end if;
  if not exists(select 1 from pg_constraint where conrelid='public.marketplace_tasks'::regclass and conname='marketplace_task_budget_chk') then
    alter table public.marketplace_tasks add constraint marketplace_task_budget_chk check (budget_amount is null or budget_amount>0);
  end if;
end $$;

alter table public.marketplace_submissions add column if not exists proposal_note text;
alter table public.marketplace_submissions add column if not exists bid_amount numeric;
alter table public.marketplace_submissions add column if not exists currency text not null default 'ETB';
alter table public.marketplace_submissions add column if not exists reviewed_at timestamptz;
alter table public.marketplace_submissions add column if not exists reviewed_by uuid references public.profiles(id) on delete set null;
alter table public.marketplace_submissions add column if not exists updated_at timestamptz not null default now();
create unique index if not exists marketplace_submissions_task_user_uidx on public.marketplace_submissions(task_id,user_id);
do $$ begin
  if not exists(select 1 from pg_constraint where conrelid='public.marketplace_submissions'::regclass and conname='marketplace_submission_status_chk') then
    alter table public.marketplace_submissions add constraint marketplace_submission_status_chk check (status in ('pending','accepted','rejected','withdrawn'));
  end if;
  if not exists(select 1 from pg_constraint where conrelid='public.marketplace_submissions'::regclass and conname='marketplace_submission_bid_chk') then
    alter table public.marketplace_submissions add constraint marketplace_submission_bid_chk check (bid_amount is null or bid_amount>0);
  end if;
end $$;

alter table public.freelance_contracts add column if not exists submission_id uuid references public.marketplace_submissions(id) on delete set null;
alter table public.freelance_contracts add column if not exists updated_at timestamptz not null default now();
create unique index if not exists freelance_contract_submission_uidx on public.freelance_contracts(submission_id) where submission_id is not null;

alter table public.task_milestones add column if not exists deliverable_url text;
alter table public.task_milestones add column if not exists submission_note text;
alter table public.task_milestones add column if not exists review_note text;
alter table public.task_milestones add column if not exists reviewed_by uuid references public.profiles(id) on delete set null;
alter table public.task_milestones add column if not exists updated_at timestamptz not null default now();
do $$ begin
  if not exists(select 1 from pg_constraint where conrelid='public.task_milestones'::regclass and conname='task_milestone_amount_chk') then
    alter table public.task_milestones add constraint task_milestone_amount_chk check (amount>0);
  end if;
end $$;

alter table public.escrow_transactions add column if not exists milestone_id uuid references public.task_milestones(id) on delete cascade;
alter table public.escrow_transactions add column if not exists funded_at timestamptz;
alter table public.escrow_transactions add column if not exists updated_at timestamptz not null default now();
create unique index if not exists escrow_milestone_uidx on public.escrow_transactions(milestone_id) where milestone_id is not null;
do $$ begin
  if not exists(select 1 from pg_constraint where conrelid='public.escrow_transactions'::regclass and conname='escrow_status_chk') then
    alter table public.escrow_transactions add constraint escrow_status_chk check (status in ('pending_funding','held','released','refunded','failed'));
  end if;
end $$;

create table if not exists public.escrow_payment_attempts (
  id uuid primary key default gen_random_uuid(), escrow_id uuid not null references public.escrow_transactions(id) on delete cascade,
  payer_id uuid not null references public.profiles(id) on delete cascade, provider text not null default 'chapa' check (provider='chapa'),
  mode text not null default 'test' check (mode in ('test','live')), tx_ref text not null unique,
  expected_amount_minor bigint not null check (expected_amount_minor>0), currency text not null default 'ETB' check (currency in ('ETB','USD')),
  status text not null default 'initiated' check (status in ('initiated','pending','success','failed','cancelled','expired')),
  checkout_url text, provider_ref text, provider_status text, verify_payload jsonb, failure_reason text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), paid_at timestamptz, last_verified_at timestamptz
);
alter table public.escrow_payment_attempts enable row level security;
create index if not exists escrow_payment_attempts_escrow_idx on public.escrow_payment_attempts(escrow_id,created_at desc);
create index if not exists escrow_payment_attempts_payer_idx on public.escrow_payment_attempts(payer_id,created_at desc);

create table if not exists public.payout_accounts (
  user_id uuid primary key references public.profiles(id) on delete cascade, account_name text not null, account_number text not null,
  bank_code text not null, bank_name text, currency text not null default 'ETB' check (currency='ETB'), active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.payout_accounts enable row level security;

create table if not exists public.payout_requests (
  id uuid primary key default gen_random_uuid(), milestone_id uuid not null references public.task_milestones(id) on delete cascade,
  escrow_id uuid not null references public.escrow_transactions(id) on delete cascade, freelancer_id uuid not null references public.profiles(id) on delete cascade,
  amount_minor bigint not null check (amount_minor>0), currency text not null default 'ETB' check (currency='ETB'), provider text not null default 'chapa' check (provider='chapa'),
  payout_ref text not null unique, status text not null default 'pending' check (status in ('pending','queued','success','failed','cancelled')),
  provider_ref text, provider_payload jsonb, failure_reason text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), completed_at timestamptz
);
alter table public.payout_requests enable row level security;
create unique index if not exists payout_requests_milestone_active_uidx on public.payout_requests(milestone_id) where status in ('pending','queued','success');

-- Task policies.
drop policy if exists "marketplace: poster manage" on public.marketplace_tasks;
drop policy if exists "Marketplace tasks public open" on public.marketplace_tasks;
drop policy if exists "Marketplace tasks authenticated read" on public.marketplace_tasks;
create policy "Marketplace tasks public open" on public.marketplace_tasks for select to anon
using (status='open' and assigned_to is null and (deadline is null or deadline>now()) and exists(select 1 from public.employers e where e.id=employer_id and e.verified=true and e.verification_status='verified'));
create policy "Marketplace tasks authenticated read" on public.marketplace_tasks for select to authenticated
using (
  (status='open' and assigned_to is null and (deadline is null or deadline>now()) and exists(select 1 from public.employers e where e.id=employer_id and e.verified=true and e.verification_status='verified'))
  or assigned_to=(select auth.uid()) or private.has_employer_access(employer_id,false) or private.is_admin_user()
);
create policy "Employer teams create marketplace tasks" on public.marketplace_tasks for insert to authenticated
with check (posted_by=(select auth.uid()) and employer_id is not null and private.has_employer_access(employer_id,true) and assigned_to is null and status in ('draft','open') and (status='draft' or exists(select 1 from public.employers e where e.id=employer_id and e.verified=true and e.verification_status='verified')));
create policy "Employer teams update marketplace tasks" on public.marketplace_tasks for update to authenticated
using (private.has_employer_access(employer_id,true) or private.is_admin_user()) with check (private.has_employer_access(employer_id,true) or private.is_admin_user());
create policy "Employer teams delete unassigned tasks" on public.marketplace_tasks for delete to authenticated
using ((private.has_employer_access(employer_id,true) or private.is_admin_user()) and status in ('draft','open','cancelled') and not exists(select 1 from public.freelance_contracts c where c.task_id=marketplace_tasks.id));
revoke insert,update,delete on public.marketplace_tasks from authenticated;
grant insert (posted_by,title,description,task_type,reward_coins,employer_id,budget_amount,currency,deadline,status,skills_required) on public.marketplace_tasks to authenticated;
grant update (title,description,task_type,reward_coins,budget_amount,currency,deadline,status,skills_required) on public.marketplace_tasks to authenticated;

create or replace function private.enforce_marketplace_task_update()
returns trigger language plpgsql set search_path='pg_catalog','public','private' as $$
declare v_system boolean := coalesce(current_setting('mela.system_workflow',true),'')='on' or current_user in ('service_role','postgres'); v_admin boolean:=private.is_admin_user();
begin
  new.updated_at=now();
  if tg_op='INSERT' then if new.status='open' then new.published_at=coalesce(new.published_at,now()); end if; return new; end if;
  if new.id is distinct from old.id or new.posted_by is distinct from old.posted_by or new.employer_id is distinct from old.employer_id or new.created_at is distinct from old.created_at then raise exception 'protected marketplace task fields cannot be changed'; end if;
  if v_system or v_admin then if new.status='open' and old.status is distinct from 'open' then new.published_at=coalesce(new.published_at,now()); end if; return new; end if;
  if new.assigned_to is distinct from old.assigned_to then raise exception 'freelancer assignment is system managed'; end if;
  if new.status is distinct from old.status then
    if not ((old.status='draft' and new.status in ('open','cancelled')) or (old.status='open' and new.status in ('draft','cancelled'))) then raise exception 'invalid marketplace task status transition'; end if;
    if new.status='open' and not exists(select 1 from public.employers e where e.id=new.employer_id and e.verified=true and e.verification_status='verified') then raise exception 'employer must be verified before publishing a task'; end if;
  end if;
  if new.status='open' and old.status is distinct from 'open' then new.published_at=now(); end if;
  return new;
end;$$;
drop trigger if exists trg_enforce_marketplace_task_update on public.marketplace_tasks;
create trigger trg_enforce_marketplace_task_update before insert or update on public.marketplace_tasks for each row execute function private.enforce_marketplace_task_update();

-- Proposal policies.
drop policy if exists "marketplace_submissions: self manage" on public.marketplace_submissions;
create policy "Marketplace submissions readable" on public.marketplace_submissions for select to authenticated
using (user_id=(select auth.uid()) or exists(select 1 from public.marketplace_tasks t where t.id=task_id and private.has_employer_access(t.employer_id,false)) or private.is_admin_user());
create policy "Students submit marketplace proposals" on public.marketplace_submissions for insert to authenticated
with check (user_id=(select auth.uid()) and status='pending' and reviewed_at is null and reviewed_by is null and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='student'::public.user_role) and exists(select 1 from public.marketplace_tasks t where t.id=task_id and t.status='open' and t.assigned_to is null and (t.deadline is null or t.deadline>now())));
create policy "Students edit or withdraw pending proposals" on public.marketplace_submissions for update to authenticated
using (user_id=(select auth.uid()) and status='pending') with check (user_id=(select auth.uid()) and status in ('pending','withdrawn'));
create policy "Employer teams review proposals" on public.marketplace_submissions for update to authenticated
using (status='pending' and exists(select 1 from public.marketplace_tasks t where t.id=task_id and private.has_employer_access(t.employer_id,true))) with check (status in ('accepted','rejected'));
create policy "Admins update proposals" on public.marketplace_submissions for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
revoke insert,update,delete on public.marketplace_submissions from authenticated;
grant insert (task_id,user_id,content_url,status,proposal_note,bid_amount,currency) on public.marketplace_submissions to authenticated;
grant update (content_url,status,proposal_note,bid_amount) on public.marketplace_submissions to authenticated;

create or replace function private.enforce_marketplace_submission_update()
returns trigger language plpgsql set search_path='pg_catalog','public','private' as $$
declare v_uid uuid:=(select auth.uid()); v_admin boolean:=private.is_admin_user(); v_employer boolean;
begin
  new.updated_at=now();
  if new.id is distinct from old.id or new.task_id is distinct from old.task_id or new.user_id is distinct from old.user_id or new.submitted_at is distinct from old.submitted_at then raise exception 'proposal identity fields cannot be changed'; end if;
  select exists(select 1 from public.marketplace_tasks t where t.id=old.task_id and private.has_employer_access(t.employer_id,true)) into v_employer;
  if v_admin or current_user in ('service_role','postgres') then return new; end if;
  if v_uid=old.user_id then
    if old.status<>'pending' or new.status not in ('pending','withdrawn') then raise exception 'student may only edit or withdraw a pending proposal'; end if;
    if new.reviewed_at is distinct from old.reviewed_at or new.reviewed_by is distinct from old.reviewed_by then raise exception 'review fields are system managed'; end if;
    return new;
  end if;
  if v_employer then
    if old.status<>'pending' or new.status not in ('accepted','rejected') then raise exception 'employer may only accept or reject a pending proposal'; end if;
    if new.content_url is distinct from old.content_url or new.proposal_note is distinct from old.proposal_note or new.bid_amount is distinct from old.bid_amount or new.currency is distinct from old.currency then raise exception 'employer cannot change freelancer proposal content'; end if;
    new.reviewed_by=v_uid; new.reviewed_at=now(); return new;
  end if;
  raise exception 'not authorized to update proposal';
end;$$;
drop trigger if exists trg_enforce_marketplace_submission_update on public.marketplace_submissions;
create trigger trg_enforce_marketplace_submission_update before update on public.marketplace_submissions for each row execute function private.enforce_marketplace_submission_update();

-- Contract creation on accepted proposal.
create or replace function private.process_accepted_marketplace_proposal()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare v_task public.marketplace_tasks%rowtype; v_contract uuid; v_amount numeric;
begin
  if new.status<>'accepted' or old.status='accepted' then return new; end if;
  select * into v_task from public.marketplace_tasks where id=new.task_id for update;
  if not found or v_task.status<>'open' or v_task.assigned_to is not null then raise exception 'task is no longer available'; end if;
  v_amount:=coalesce(new.bid_amount,v_task.budget_amount);
  if v_amount is null or v_amount<=0 then raise exception 'accepted proposal requires a positive budget'; end if;
  if new.currency<>v_task.currency then raise exception 'proposal currency must match task currency'; end if;
  perform set_config('mela.system_workflow','on',true);
  update public.marketplace_tasks set assigned_to=new.user_id,status='assigned' where id=v_task.id;
  insert into public.freelance_contracts(task_id,submission_id,employer_id,freelancer_id,agreed_amount,currency,terms,status)
  values(v_task.id,new.id,v_task.employer_id,new.user_id,v_amount,new.currency,'Accepted Mela marketplace proposal','active') returning id into v_contract;
  insert into public.task_milestones(contract_id,milestone_order,title,description,amount,due_at,status)
  values(v_contract,1,'Project delivery',coalesce(v_task.description,'Complete the agreed task.'),v_amount,v_task.deadline,'pending');
  update public.marketplace_submissions set status='rejected',reviewed_at=now(),reviewed_by=coalesce(new.reviewed_by,(select auth.uid())),updated_at=now() where task_id=v_task.id and id<>new.id and status='pending';
  perform private.create_notification(new.user_id,'Freelance proposal accepted','Your proposal was accepted. The contract is active and awaits escrow funding.','freelance_contracts',v_contract);
  perform private.create_notification(v_task.posted_by,'Freelance contract created','Fund escrow before approving freelancer delivery.','freelance_contracts',v_contract);
  return new;
end;$$;
revoke all on function private.process_accepted_marketplace_proposal() from public,anon,authenticated;
drop trigger if exists trg_process_accepted_marketplace_proposal on public.marketplace_submissions;
create trigger trg_process_accepted_marketplace_proposal after update of status on public.marketplace_submissions for each row execute function private.process_accepted_marketplace_proposal();

-- Contracts.
drop policy if exists "Employer teams create contracts" on public.freelance_contracts;
drop policy if exists "Employer teams delete contracts" on public.freelance_contracts;
drop policy if exists "Employer teams update contracts" on public.freelance_contracts;
drop policy if exists "Contracts readable by participants" on public.freelance_contracts;
create policy "Contracts readable by participants" on public.freelance_contracts for select to authenticated using (freelancer_id=(select auth.uid()) or private.has_employer_access(employer_id,false) or private.is_admin_user());
create policy "Employer teams update contracts" on public.freelance_contracts for update to authenticated using (private.has_employer_access(employer_id,true) or private.is_admin_user()) with check (private.has_employer_access(employer_id,true) or private.is_admin_user());
revoke insert,update,delete on public.freelance_contracts from authenticated;
grant update (terms,status) on public.freelance_contracts to authenticated;
create or replace function private.enforce_freelance_contract_update()
returns trigger language plpgsql set search_path='pg_catalog','public','private' as $$
declare v_system boolean:=coalesce(current_setting('mela.system_workflow',true),'')='on' or current_user in ('service_role','postgres'); v_admin boolean:=private.is_admin_user();
begin
  new.updated_at=now();
  if new.id is distinct from old.id or new.task_id is distinct from old.task_id or new.submission_id is distinct from old.submission_id or new.employer_id is distinct from old.employer_id or new.freelancer_id is distinct from old.freelancer_id or new.agreed_amount is distinct from old.agreed_amount or new.currency is distinct from old.currency or new.started_at is distinct from old.started_at or new.created_at is distinct from old.created_at then raise exception 'protected contract fields cannot be changed'; end if;
  if v_system or v_admin then return new; end if;
  if new.status is distinct from old.status and not (old.status='active' and new.status in ('cancelled','disputed')) then raise exception 'invalid contract status transition'; end if;
  if new.status='cancelled' and exists(select 1 from public.task_milestones m where m.contract_id=old.id and m.status in ('submitted','approved','paid')) then raise exception 'contract with submitted work cannot be cancelled directly'; end if;
  if new.status='cancelled' and exists(select 1 from public.escrow_transactions e where e.contract_id=old.id and e.status='held') then raise exception 'funded escrow must be refunded before cancellation'; end if;
  return new;
end;$$;
drop trigger if exists trg_enforce_freelance_contract_update on public.freelance_contracts;
create trigger trg_enforce_freelance_contract_update before update on public.freelance_contracts for each row execute function private.enforce_freelance_contract_update();

-- Milestones.
drop policy if exists "Employer teams delete milestones" on public.task_milestones;
drop policy if exists "Employer teams insert milestones" on public.task_milestones;
drop policy if exists "Milestones readable by contract participants" on public.task_milestones;
drop policy if exists "Employer teams update milestones" on public.task_milestones;
create policy "Milestones readable by participants" on public.task_milestones for select to authenticated using (exists(select 1 from public.freelance_contracts c where c.id=contract_id and (c.freelancer_id=(select auth.uid()) or private.has_employer_access(c.employer_id,false) or private.is_admin_user())));
create policy "Employer teams create milestones" on public.task_milestones for insert to authenticated with check (exists(select 1 from public.freelance_contracts c where c.id=contract_id and c.status='active' and (private.has_employer_access(c.employer_id,true) or private.is_admin_user())));
create policy "Participants update milestones" on public.task_milestones for update to authenticated using (exists(select 1 from public.freelance_contracts c where c.id=contract_id and (c.freelancer_id=(select auth.uid()) or private.has_employer_access(c.employer_id,true) or private.is_admin_user()))) with check (exists(select 1 from public.freelance_contracts c where c.id=contract_id and (c.freelancer_id=(select auth.uid()) or private.has_employer_access(c.employer_id,true) or private.is_admin_user())));
create policy "Employer teams delete pending milestones" on public.task_milestones for delete to authenticated using (status='pending' and exists(select 1 from public.freelance_contracts c where c.id=contract_id and (private.has_employer_access(c.employer_id,true) or private.is_admin_user())) and not exists(select 1 from public.escrow_transactions e where e.milestone_id=task_milestones.id and e.status<>'pending_funding'));
revoke insert,update,delete on public.task_milestones from authenticated;
grant insert (contract_id,milestone_order,title,description,amount,due_at,status) on public.task_milestones to authenticated;
grant update (milestone_order,title,description,amount,due_at,status,deliverable_url,submission_note,review_note) on public.task_milestones to authenticated;

create or replace function private.enforce_task_milestone_change()
returns trigger language plpgsql set search_path='pg_catalog','public','private' as $$
declare v_uid uuid:=(select auth.uid()); v_contract public.freelance_contracts%rowtype; v_system boolean:=coalesce(current_setting('mela.system_workflow',true),'')='on' or current_user in ('service_role','postgres'); v_admin boolean:=private.is_admin_user(); v_other numeric;
begin
  select * into v_contract from public.freelance_contracts where id=coalesce(new.contract_id,old.contract_id);
  if tg_op='INSERT' then
    if not v_system and not v_admin and not private.has_employer_access(v_contract.employer_id,true) then raise exception 'only employer team can create milestones'; end if;
    select coalesce(sum(amount),0) into v_other from public.task_milestones where contract_id=new.contract_id;
    if v_other+new.amount>v_contract.agreed_amount then raise exception 'milestone amounts exceed contract total'; end if;
    new.status:='pending'; new.submitted_at:=null; new.approved_at:=null; new.reviewed_by:=null; new.updated_at:=now(); return new;
  end if;
  new.updated_at=now();
  if new.id is distinct from old.id or new.contract_id is distinct from old.contract_id or new.created_at is distinct from old.created_at then raise exception 'protected milestone fields cannot be changed'; end if;
  if v_system or v_admin then return new; end if;
  if v_uid=v_contract.freelancer_id then
    if new.title is distinct from old.title or new.description is distinct from old.description or new.amount is distinct from old.amount or new.due_at is distinct from old.due_at or new.milestone_order is distinct from old.milestone_order or new.review_note is distinct from old.review_note or new.reviewed_by is distinct from old.reviewed_by or new.approved_at is distinct from old.approved_at then raise exception 'freelancer cannot edit milestone terms/review fields'; end if;
    if new.status is distinct from old.status then
      if not (old.status in ('pending','in_progress','rejected') and new.status in ('in_progress','submitted')) then raise exception 'invalid freelancer milestone transition'; end if;
      if new.status='submitted' and coalesce(new.deliverable_url,'')='' then raise exception 'deliverable_url is required to submit a milestone'; end if;
      if new.status='submitted' then new.submitted_at=now(); end if;
    end if;
    return new;
  end if;
  if private.has_employer_access(v_contract.employer_id,true) then
    if new.deliverable_url is distinct from old.deliverable_url or new.submission_note is distinct from old.submission_note or new.submitted_at is distinct from old.submitted_at then raise exception 'employer cannot alter freelancer submission evidence'; end if;
    if old.status='pending' then
      select coalesce(sum(amount),0) into v_other from public.task_milestones where contract_id=old.contract_id and id<>old.id;
      if v_other+new.amount>v_contract.agreed_amount then raise exception 'milestone amounts exceed contract total'; end if;
    elsif new.title is distinct from old.title or new.description is distinct from old.description or new.amount is distinct from old.amount or new.due_at is distinct from old.due_at or new.milestone_order is distinct from old.milestone_order then raise exception 'milestone terms are locked after work starts'; end if;
    if new.status is distinct from old.status then
      if not (old.status='submitted' and new.status in ('approved','rejected')) then raise exception 'employer may only approve or reject submitted work'; end if;
      if new.status='approved' then
        if not exists(select 1 from public.escrow_transactions e where e.milestone_id=old.id and e.status='held') then raise exception 'escrow must be funded before approval'; end if;
        new.approved_at=now(); new.reviewed_by=v_uid;
      elsif new.status='rejected' then new.reviewed_by=v_uid; end if;
    end if;
    return new;
  end if;
  raise exception 'not authorized';
end;$$;
drop trigger if exists trg_enforce_task_milestone_change on public.task_milestones;
create trigger trg_enforce_task_milestone_change before insert or update on public.task_milestones for each row execute function private.enforce_task_milestone_change();

create or replace function private.sync_escrow_from_milestone()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare v_contract public.freelance_contracts%rowtype; v_task public.marketplace_tasks%rowtype;
begin
  select * into v_contract from public.freelance_contracts where id=new.contract_id;
  select * into v_task from public.marketplace_tasks where id=v_contract.task_id;
  if tg_op='INSERT' then
    insert into public.escrow_transactions(task_id,user_id,amount_coins,status,contract_id,amount_minor,currency,provider,milestone_id)
    values(v_contract.task_id,v_contract.freelancer_id,coalesce(v_task.reward_coins,0),'pending_funding',v_contract.id,round(new.amount*100)::bigint,v_contract.currency,'chapa',new.id)
    on conflict (milestone_id) where milestone_id is not null do nothing;
  elsif new.amount is distinct from old.amount then
    update public.escrow_transactions set amount_minor=round(new.amount*100)::bigint,updated_at=now() where milestone_id=new.id and status='pending_funding';
  end if;
  return new;
end;$$;
revoke all on function private.sync_escrow_from_milestone() from public,anon,authenticated;
drop trigger if exists trg_sync_escrow_from_milestone on public.task_milestones;
create trigger trg_sync_escrow_from_milestone after insert or update of amount on public.task_milestones for each row execute function private.sync_escrow_from_milestone();

create or replace function private.process_milestone_status()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare v_contract public.freelance_contracts%rowtype; v_escrow uuid; v_minor bigint; v_ref text;
begin
  if new.status is not distinct from old.status then return new; end if;
  select * into v_contract from public.freelance_contracts where id=new.contract_id;
  if new.status='submitted' then
    perform private.create_notification((select posted_by from public.marketplace_tasks where id=v_contract.task_id),'Freelance milestone submitted','The freelancer submitted a milestone for review.','task_milestones',new.id);
  elsif new.status='rejected' then
    perform private.create_notification(v_contract.freelancer_id,'Freelance milestone needs changes',coalesce(new.review_note,'The employer requested revisions.'),'task_milestones',new.id);
  elsif new.status='approved' then
    select id,amount_minor into v_escrow,v_minor from public.escrow_transactions where milestone_id=new.id and status='held' limit 1;
    v_ref:='mela_payout_'||replace(gen_random_uuid()::text,'-','');
    insert into public.payout_requests(milestone_id,escrow_id,freelancer_id,amount_minor,currency,payout_ref,status)
    values(new.id,v_escrow,v_contract.freelancer_id,v_minor,v_contract.currency,v_ref,'pending') on conflict do nothing;
    perform private.create_notification(v_contract.freelancer_id,'Milestone approved','Your milestone was approved. Payout is being prepared.','task_milestones',new.id);
  elsif new.status='paid' then
    perform private.create_notification(v_contract.freelancer_id,'Freelance payout completed','Payment for your milestone was released.','task_milestones',new.id);
  end if;
  return new;
end;$$;
revoke all on function private.process_milestone_status() from public,anon,authenticated;
drop trigger if exists trg_process_milestone_status on public.task_milestones;
create trigger trg_process_milestone_status after update of status on public.task_milestones for each row execute function private.process_milestone_status();

-- Financial-row access.
drop policy if exists "escrow: self read" on public.escrow_transactions;
create policy "Escrow readable by contract participants" on public.escrow_transactions for select to authenticated
using (user_id=(select auth.uid()) or exists(select 1 from public.freelance_contracts c where c.id=contract_id and private.has_employer_access(c.employer_id,false)) or private.is_admin_user());
revoke insert,update,delete on public.escrow_transactions from authenticated,anon;

create policy "Escrow payment attempts readable" on public.escrow_payment_attempts for select to authenticated
using (payer_id=(select auth.uid()) or exists(select 1 from public.escrow_transactions e join public.freelance_contracts c on c.id=e.contract_id where e.id=escrow_id and private.has_employer_access(c.employer_id,false)) or private.is_admin_user());
grant select on public.escrow_payment_attempts to authenticated; revoke insert,update,delete on public.escrow_payment_attempts from authenticated,anon;

create policy "Payout account owner read" on public.payout_accounts for select to authenticated using (user_id=(select auth.uid()) or private.is_admin_user());
create policy "Payout account owner insert" on public.payout_accounts for insert to authenticated with check (user_id=(select auth.uid()));
create policy "Payout account owner update" on public.payout_accounts for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy "Payout account owner delete" on public.payout_accounts for delete to authenticated using (user_id=(select auth.uid()));
grant select,insert,update,delete on public.payout_accounts to authenticated; revoke all on public.payout_accounts from anon;

create policy "Payout requests readable by participants" on public.payout_requests for select to authenticated
using (freelancer_id=(select auth.uid()) or exists(select 1 from public.task_milestones m join public.freelance_contracts c on c.id=m.contract_id where m.id=milestone_id and private.has_employer_access(c.employer_id,false)) or private.is_admin_user());
grant select on public.payout_requests to authenticated; revoke insert,update,delete on public.payout_requests from authenticated,anon;

create or replace function private.touch_financial_rows()
returns trigger language plpgsql set search_path='pg_catalog','public' as $$ begin new.updated_at=now(); return new; end; $$;
drop trigger if exists trg_touch_escrow_payment_attempts on public.escrow_payment_attempts;
create trigger trg_touch_escrow_payment_attempts before update on public.escrow_payment_attempts for each row execute function private.touch_financial_rows();
drop trigger if exists trg_touch_payout_accounts on public.payout_accounts;
create trigger trg_touch_payout_accounts before update on public.payout_accounts for each row execute function private.touch_financial_rows();
drop trigger if exists trg_touch_payout_requests on public.payout_requests;
create trigger trg_touch_payout_requests before update on public.payout_requests for each row execute function private.touch_financial_rows();

create index if not exists marketplace_tasks_employer_status_idx on public.marketplace_tasks(employer_id,status,created_at desc);
create index if not exists marketplace_tasks_assigned_status_idx on public.marketplace_tasks(assigned_to,status);
create index if not exists marketplace_submissions_task_status_idx on public.marketplace_submissions(task_id,status,submitted_at desc);
create index if not exists freelance_contracts_freelancer_status_idx on public.freelance_contracts(freelancer_id,status,created_at desc);
create index if not exists task_milestones_contract_status_idx on public.task_milestones(contract_id,status,milestone_order);
create index if not exists escrow_transactions_contract_status_idx on public.escrow_transactions(contract_id,status);
create index if not exists payout_requests_freelancer_status_idx on public.payout_requests(freelancer_id,status,created_at desc);

;

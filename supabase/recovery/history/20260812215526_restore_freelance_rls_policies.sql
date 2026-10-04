-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812215526
-- Restore the intended freelance RLS policies from current live state.

-- Tasks.
drop policy if exists "Marketplace tasks public open" on public.marketplace_tasks;
drop policy if exists "Marketplace tasks authenticated read" on public.marketplace_tasks;
drop policy if exists "Employer teams create marketplace tasks" on public.marketplace_tasks;
drop policy if exists "Employer teams update marketplace tasks" on public.marketplace_tasks;
drop policy if exists "Employer teams delete unassigned tasks" on public.marketplace_tasks;
drop policy if exists "marketplace: poster manage" on public.marketplace_tasks;
create policy "Marketplace tasks public open" on public.marketplace_tasks for select to anon
using (status='open' and assigned_to is null and (deadline is null or deadline>now()) and exists(select 1 from public.employers e where e.id=employer_id and e.verified=true and e.verification_status='verified'));
create policy "Marketplace tasks authenticated read" on public.marketplace_tasks for select to authenticated
using ((status='open' and assigned_to is null and (deadline is null or deadline>now()) and exists(select 1 from public.employers e where e.id=employer_id and e.verified=true and e.verification_status='verified')) or assigned_to=(select auth.uid()) or private.has_employer_access(employer_id,false) or private.is_admin_user());
create policy "Employer teams create marketplace tasks" on public.marketplace_tasks for insert to authenticated
with check (posted_by=(select auth.uid()) and employer_id is not null and private.has_employer_access(employer_id,true) and assigned_to is null and status in ('draft','open') and (status='draft' or exists(select 1 from public.employers e where e.id=employer_id and e.verified=true and e.verification_status='verified')));
create policy "Employer teams update marketplace tasks" on public.marketplace_tasks for update to authenticated
using (private.has_employer_access(employer_id,true) or private.is_admin_user()) with check (private.has_employer_access(employer_id,true) or private.is_admin_user());
create policy "Employer teams delete unassigned tasks" on public.marketplace_tasks for delete to authenticated
using ((private.has_employer_access(employer_id,true) or private.is_admin_user()) and status in ('draft','open','cancelled','expired') and not exists(select 1 from public.freelance_contracts c where c.task_id=marketplace_tasks.id));

-- Proposals.
drop policy if exists "Students submit freelance proposals" on public.marketplace_submissions;
drop policy if exists "Marketplace submissions readable by participants" on public.marketplace_submissions;
drop policy if exists "Marketplace submissions readable" on public.marketplace_submissions;
drop policy if exists "Students submit marketplace proposals" on public.marketplace_submissions;
drop policy if exists "Students edit or withdraw pending proposals" on public.marketplace_submissions;
drop policy if exists "Employer teams review proposals" on public.marketplace_submissions;
drop policy if exists "Admins update proposals" on public.marketplace_submissions;
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

-- Contracts.
drop policy if exists "Contracts readable by participants" on public.freelance_contracts;
drop policy if exists "Employer teams update contracts" on public.freelance_contracts;
drop policy if exists "Employer teams create contracts" on public.freelance_contracts;
drop policy if exists "Employer teams delete contracts" on public.freelance_contracts;
create policy "Contracts readable by participants" on public.freelance_contracts for select to authenticated
using (freelancer_id=(select auth.uid()) or private.has_employer_access(employer_id,false) or private.is_admin_user());
create policy "Employer teams update contracts" on public.freelance_contracts for update to authenticated
using (private.has_employer_access(employer_id,true) or private.is_admin_user()) with check (private.has_employer_access(employer_id,true) or private.is_admin_user());

-- Milestones.
drop policy if exists "Milestones readable by participants" on public.task_milestones;
drop policy if exists "Milestones readable by contract participants" on public.task_milestones;
drop policy if exists "Employer teams create milestones" on public.task_milestones;
drop policy if exists "Participants update milestones" on public.task_milestones;
drop policy if exists "Employer teams update milestones" on public.task_milestones;
drop policy if exists "Employer teams insert milestones" on public.task_milestones;
drop policy if exists "Employer teams delete pending milestones" on public.task_milestones;
drop policy if exists "Employer teams delete milestones" on public.task_milestones;
create policy "Milestones readable by participants" on public.task_milestones for select to authenticated
using (exists(select 1 from public.freelance_contracts c where c.id=contract_id and (c.freelancer_id=(select auth.uid()) or private.has_employer_access(c.employer_id,false) or private.is_admin_user())));
create policy "Employer teams create milestones" on public.task_milestones for insert to authenticated
with check (exists(select 1 from public.freelance_contracts c where c.id=contract_id and c.status='active' and (private.has_employer_access(c.employer_id,true) or private.is_admin_user())));
create policy "Participants update milestones" on public.task_milestones for update to authenticated
using (exists(select 1 from public.freelance_contracts c where c.id=contract_id and (c.freelancer_id=(select auth.uid()) or private.has_employer_access(c.employer_id,true) or private.is_admin_user())))
with check (exists(select 1 from public.freelance_contracts c where c.id=contract_id and (c.freelancer_id=(select auth.uid()) or private.has_employer_access(c.employer_id,true) or private.is_admin_user())));
create policy "Employer teams delete pending milestones" on public.task_milestones for delete to authenticated
using (status='pending' and exists(select 1 from public.freelance_contracts c where c.id=contract_id and (private.has_employer_access(c.employer_id,true) or private.is_admin_user())) and not exists(select 1 from public.escrow_transactions e where e.milestone_id=task_milestones.id and e.status<>'pending_funding'));

-- Escrow participant visibility.
drop policy if exists "Escrow readable by contract participants" on public.escrow_transactions;
drop policy if exists "escrow: self read" on public.escrow_transactions;
create policy "Escrow readable by contract participants" on public.escrow_transactions for select to authenticated
using (user_id=(select auth.uid()) or exists(select 1 from public.freelance_contracts c where c.id=contract_id and private.has_employer_access(c.employer_id,false)) or private.is_admin_user());

;

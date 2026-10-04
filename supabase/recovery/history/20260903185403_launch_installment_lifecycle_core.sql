-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260903185403
create table if not exists public.installment_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  reference_type text not null default 'purchase',
  reference_id uuid,
  currency text not null default 'ETB' check (currency ~ '^[A-Z]{3}$'),
  principal_minor bigint not null check (principal_minor > 0),
  total_due_minor bigint not null check (total_due_minor >= principal_minor),
  installment_count integer not null check (installment_count between 1 and 60),
  frequency text not null check (frequency in ('weekly','biweekly','monthly')),
  status text not null default 'active' check (status in ('pending','active','completed','overdue','cancelled','defaulted')),
  next_due_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.installment_schedule (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.installment_plans(id) on delete cascade,
  sequence_no integer not null check (sequence_no >= 1),
  due_at timestamptz not null,
  amount_minor bigint not null check (amount_minor > 0),
  status text not null default 'pending' check (status in ('pending','paid','overdue','cancelled')),
  payment_id uuid references public.payments(id) on delete set null,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(plan_id, sequence_no)
);

create index if not exists installment_plans_user_status_idx on public.installment_plans(user_id,status);
create index if not exists installment_schedule_due_status_idx on public.installment_schedule(due_at,status);

alter table public.installment_plans enable row level security;
alter table public.installment_schedule enable row level security;

drop policy if exists installment_plans_owner_select on public.installment_plans;
create policy installment_plans_owner_select on public.installment_plans for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists installment_plans_owner_insert on public.installment_plans;
create policy installment_plans_owner_insert on public.installment_plans for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists installment_plans_owner_update on public.installment_plans;
create policy installment_plans_owner_update on public.installment_plans for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists installment_schedule_owner_select on public.installment_schedule;
create policy installment_schedule_owner_select on public.installment_schedule for select to authenticated using (exists (select 1 from public.installment_plans p where p.id=plan_id and p.user_id=(select auth.uid())));

create or replace function public.refresh_installment_overdue(p_plan_id uuid default null)
returns integer language plpgsql security definer set search_path=public
as $$
declare n integer;
begin
  update public.installment_schedule s set status='overdue',updated_at=now()
  where (p_plan_id is null or s.plan_id=p_plan_id) and s.status='pending' and s.due_at < now();
  get diagnostics n = row_count;
  update public.installment_plans p set status='overdue',updated_at=now()
  where (p_plan_id is null or p.id=p_plan_id) and p.status='active' and exists(select 1 from public.installment_schedule s where s.plan_id=p.id and s.status='overdue');
  return n;
end; $$;
revoke all on function public.refresh_installment_overdue(uuid) from public,anon,authenticated;
grant execute on function public.refresh_installment_overdue(uuid) to service_role;
;

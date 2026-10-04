-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812221219
-- Earn & Work reputation and immutable earnings history.
create table if not exists public.work_reviews (
  id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references public.freelance_contracts(id) on delete cascade,
  reviewer_user_id uuid not null references public.profiles(id) on delete cascade,
  reviewee_user_id uuid references public.profiles(id) on delete cascade,
  reviewee_employer_id uuid references public.employers(id) on delete cascade,
  rating smallint not null check(rating between 1 and 5),
  quality_rating smallint check(quality_rating between 1 and 5),
  communication_rating smallint check(communication_rating between 1 and 5),
  timeliness_rating smallint check(timeliness_rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  constraint work_review_one_subject_chk check ((reviewee_user_id is not null)::int + (reviewee_employer_id is not null)::int = 1)
);
create unique index if not exists work_reviews_contract_reviewer_user_uidx on public.work_reviews(contract_id,reviewer_user_id,reviewee_user_id) where reviewee_user_id is not null;
create unique index if not exists work_reviews_contract_reviewer_employer_uidx on public.work_reviews(contract_id,reviewer_user_id,reviewee_employer_id) where reviewee_employer_id is not null;

create table if not exists public.work_reputation (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  rating_average numeric(3,2) not null default 0,
  review_count integer not null default 0,
  completed_contracts integer not null default 0,
  total_earned numeric not null default 0,
  currency text not null default 'ETB',
  updated_at timestamptz not null default now()
);
create table if not exists public.employer_work_reputation (
  employer_id uuid primary key references public.employers(id) on delete cascade,
  rating_average numeric(3,2) not null default 0,
  review_count integer not null default 0,
  completed_contracts integer not null default 0,
  updated_at timestamptz not null default now()
);
create table if not exists public.earnings_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  source_type text not null check(source_type in ('freelance_milestone','challenge_reward','adjustment')),
  source_id uuid not null,
  gross_amount numeric not null check(gross_amount>=0),
  platform_fee numeric not null default 0 check(platform_fee>=0),
  net_amount numeric not null check(net_amount>=0),
  currency text not null default 'ETB',
  status text not null default 'available' check(status in ('pending','available','paid','reversed')),
  external_ref text,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create unique index if not exists earnings_ledger_source_user_uidx on public.earnings_ledger(source_type,source_id,user_id);
create index if not exists work_reviews_reviewee_user_idx on public.work_reviews(reviewee_user_id,created_at desc);
create index if not exists work_reviews_reviewee_employer_idx on public.work_reviews(reviewee_employer_id,created_at desc);
create index if not exists earnings_ledger_user_status_idx on public.earnings_ledger(user_id,status,occurred_at desc);

alter table public.work_reviews enable row level security;
alter table public.work_reputation enable row level security;
alter table public.employer_work_reputation enable row level security;
alter table public.earnings_ledger enable row level security;
revoke all on public.work_reviews,public.work_reputation,public.employer_work_reputation,public.earnings_ledger from anon,authenticated;
grant select on public.work_reviews,public.work_reputation,public.employer_work_reputation,public.earnings_ledger to authenticated;
grant select on public.work_reputation,public.employer_work_reputation to anon;
grant all on public.work_reviews,public.work_reputation,public.employer_work_reputation,public.earnings_ledger to service_role;

drop policy if exists "Work reviews participants read" on public.work_reviews;
create policy "Work reviews participants read" on public.work_reviews for select to authenticated using(reviewer_user_id=(select auth.uid()) or reviewee_user_id=(select auth.uid()) or (reviewee_employer_id is not null and private.has_employer_access(reviewee_employer_id,false)) or private.is_admin_user());
drop policy if exists "Worker reputation public" on public.work_reputation;
create policy "Worker reputation public" on public.work_reputation for select to anon,authenticated using(true);
drop policy if exists "Employer work reputation public" on public.employer_work_reputation;
create policy "Employer work reputation public" on public.employer_work_reputation for select to anon,authenticated using(true);
drop policy if exists "Earnings owner read" on public.earnings_ledger;
create policy "Earnings owner read" on public.earnings_ledger for select to authenticated using(user_id=(select auth.uid()) or private.is_admin_user());

create or replace function private.refresh_work_reputation(p_user_id uuid,p_employer_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ begin
 if p_user_id is not null then
   insert into public.work_reputation(user_id,rating_average,review_count,completed_contracts,total_earned,currency,updated_at)
   select p_user_id,coalesce(avg(r.rating),0)::numeric(3,2),count(r.id)::int,(select count(*) from public.freelance_contracts c where c.freelancer_id=p_user_id and c.status='completed'),coalesce((select sum(e.net_amount) from public.earnings_ledger e where e.user_id=p_user_id and e.status in ('available','paid')),0),'ETB',now()
   from public.work_reviews r where r.reviewee_user_id=p_user_id
   on conflict(user_id) do update set rating_average=excluded.rating_average,review_count=excluded.review_count,completed_contracts=excluded.completed_contracts,total_earned=excluded.total_earned,updated_at=now();
 end if;
 if p_employer_id is not null then
   insert into public.employer_work_reputation(employer_id,rating_average,review_count,completed_contracts,updated_at)
   select p_employer_id,coalesce(avg(r.rating),0)::numeric(3,2),count(r.id)::int,(select count(*) from public.freelance_contracts c where c.employer_id=p_employer_id and c.status='completed'),now()
   from public.work_reviews r where r.reviewee_employer_id=p_employer_id
   on conflict(employer_id) do update set rating_average=excluded.rating_average,review_count=excluded.review_count,completed_contracts=excluded.completed_contracts,updated_at=now();
 end if;
end $$;

create or replace function private.submit_work_review(p_contract_id uuid,p_rating int,p_comment text,p_quality int,p_communication int,p_timeliness int)
returns public.work_reviews language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_c public.freelance_contracts; v public.work_reviews; begin
 if v_uid is null then raise exception 'authentication required'; end if;
 select * into v_c from public.freelance_contracts where id=p_contract_id;
 if v_c.id is null or v_c.status<>'completed' then raise exception 'completed contract required'; end if;
 if p_rating<1 or p_rating>5 then raise exception 'rating must be 1 to 5'; end if;
 if v_uid=v_c.freelancer_id then
   insert into public.work_reviews(contract_id,reviewer_user_id,reviewee_employer_id,rating,comment,quality_rating,communication_rating,timeliness_rating) values(p_contract_id,v_uid,v_c.employer_id,p_rating,p_comment,p_quality,p_communication,p_timeliness) returning * into v;
   perform private.refresh_work_reputation(null,v_c.employer_id);
 elsif private.has_employer_access(v_c.employer_id,true) then
   insert into public.work_reviews(contract_id,reviewer_user_id,reviewee_user_id,rating,comment,quality_rating,communication_rating,timeliness_rating) values(p_contract_id,v_uid,v_c.freelancer_id,p_rating,p_comment,p_quality,p_communication,p_timeliness) returning * into v;
   perform private.refresh_work_reputation(v_c.freelancer_id,null);
 else raise exception 'contract participant access required'; end if;
 return v; end $$;
create or replace function public.submit_work_review(p_contract_id uuid,p_rating int,p_comment text default null,p_quality int default null,p_communication int default null,p_timeliness int default null) returns public.work_reviews language sql security invoker set search_path='' as $$ select private.submit_work_review(p_contract_id,p_rating,p_comment,p_quality,p_communication,p_timeliness); $$;

create or replace function private.ledger_from_payout_success()
returns trigger language plpgsql security definer set search_path=''
as $$ declare v_amount numeric; begin
 if new.status='success' and old.status is distinct from new.status then
   v_amount:=new.amount_minor/100.0;
   insert into public.earnings_ledger(user_id,source_type,source_id,gross_amount,platform_fee,net_amount,currency,status,external_ref,occurred_at) values(new.freelancer_id,'freelance_milestone',new.milestone_id,v_amount,0,v_amount,new.currency,'paid',coalesce(new.provider_ref,new.payout_ref),coalesce(new.completed_at,now())) on conflict(source_type,source_id,user_id) do nothing;
   perform private.refresh_work_reputation(new.freelancer_id,null);
 end if; return new; end $$;
drop trigger if exists trg_ledger_from_payout_success on public.payout_requests;
create trigger trg_ledger_from_payout_success after update on public.payout_requests for each row execute function private.ledger_from_payout_success();

create or replace function private.ledger_from_challenge_reward()
returns trigger language plpgsql security definer set search_path=''
as $$ declare r record; v_count int; v_each numeric; begin
 if new.status='paid' and (tg_op='INSERT' or old.status is distinct from new.status) then
   if new.beneficiary_user_id is not null then
     insert into public.earnings_ledger(user_id,source_type,source_id,gross_amount,platform_fee,net_amount,currency,status,external_ref,occurred_at) values(new.beneficiary_user_id,'challenge_reward',new.id,new.amount,0,new.amount,new.currency,'paid',new.external_ref,coalesce(new.paid_at,now())) on conflict(source_type,source_id,user_id) do nothing;
     perform private.refresh_work_reputation(new.beneficiary_user_id,null);
   elsif new.beneficiary_team_id is not null then
     select count(*) into v_count from public.challenge_team_members where team_id=new.beneficiary_team_id;
     if v_count>0 then v_each:=new.amount/v_count;
       for r in select user_id from public.challenge_team_members where team_id=new.beneficiary_team_id loop
         insert into public.earnings_ledger(user_id,source_type,source_id,gross_amount,platform_fee,net_amount,currency,status,external_ref,occurred_at) values(r.user_id,'challenge_reward',new.id,v_each,0,v_each,new.currency,'paid',new.external_ref,coalesce(new.paid_at,now())) on conflict(source_type,source_id,user_id) do nothing;
         perform private.refresh_work_reputation(r.user_id,null);
       end loop;
     end if;
   end if;
 end if; return new; end $$;
drop trigger if exists trg_ledger_from_challenge_reward on public.challenge_rewards;
create trigger trg_ledger_from_challenge_reward after insert or update on public.challenge_rewards for each row execute function private.ledger_from_challenge_reward();

-- AI Career Coach structured plan/action layer.
create table if not exists public.career_coach_action_plans (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  session_id uuid references public.career_coach_sessions(id) on delete set null, title text not null, goal text,
  status text not null default 'active' check(status in ('active','completed','archived')), target_date date,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.career_coach_action_items (
  id uuid primary key default gen_random_uuid(), plan_id uuid not null references public.career_coach_action_plans(id) on delete cascade,
  title text not null, item_type text not null default 'learn' check(item_type in ('learn','assess','build','apply','network','interview','scholarship','work')),
  priority smallint not null default 2 check(priority between 1 and 3), status text not null default 'todo' check(status in ('todo','in_progress','done','skipped')),
  due_at timestamptz, related_table text, related_id uuid, notes text, completed_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists coach_action_plans_user_status_idx on public.career_coach_action_plans(user_id,status,updated_at desc);
create index if not exists coach_action_items_plan_status_idx on public.career_coach_action_items(plan_id,status,due_at);
alter table public.career_coach_action_plans enable row level security;
alter table public.career_coach_action_items enable row level security;
revoke all on public.career_coach_action_plans,public.career_coach_action_items from anon,authenticated;
grant select,insert,update,delete on public.career_coach_action_plans,public.career_coach_action_items to authenticated;
grant all on public.career_coach_action_plans,public.career_coach_action_items to service_role;
drop policy if exists "Coach plans owner manage" on public.career_coach_action_plans;
create policy "Coach plans owner manage" on public.career_coach_action_plans for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
drop policy if exists "Coach action items owner manage" on public.career_coach_action_items;
create policy "Coach action items owner manage" on public.career_coach_action_items for all to authenticated using(exists(select 1 from public.career_coach_action_plans p where p.id=plan_id and p.user_id=(select auth.uid()))) with check(exists(select 1 from public.career_coach_action_plans p where p.id=plan_id and p.user_id=(select auth.uid())));

do $$ declare r record; begin for r in select n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public' and p.proname='submit_work_review') or (n.nspname='private' and p.proname='submit_work_review') loop execute format('revoke all on function %I.%I(%s) from public,anon',r.nspname,r.proname,r.args); execute format('grant execute on function %I.%I(%s) to authenticated,service_role',r.nspname,r.proname,r.args); end loop; end $$;
;

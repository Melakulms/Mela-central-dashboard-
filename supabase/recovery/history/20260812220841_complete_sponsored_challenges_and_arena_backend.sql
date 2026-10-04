-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812220841
-- Sponsored Challenges completion
alter table public.sponsored_challenges
  add column if not exists sponsor_employer_id uuid references public.employers(id) on delete set null,
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists challenge_type text not null default 'innovation',
  add column if not exists category public.launch_category,
  add column if not exists status text not null default 'draft',
  add column if not exists eligibility_rules jsonb not null default '{}'::jsonb,
  add column if not exists judging_criteria jsonb not null default '[]'::jsonb,
  add column if not exists submission_requirements text[] not null default '{}',
  add column if not exists team_mode boolean not null default false,
  add column if not exists min_team_size integer not null default 1,
  add column if not exists max_team_size integer not null default 1,
  add column if not exists max_participants integer,
  add column if not exists prize_currency text not null default 'ETB',
  add column if not exists published_at timestamptz,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists winner_submission_id uuid;

do $$ begin
  alter table public.sponsored_challenges add constraint sponsored_challenge_status_chk check (status in ('draft','published','open','judging','completed','cancelled'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.sponsored_challenges add constraint sponsored_challenge_type_chk check (challenge_type in ('innovation','case_study','hackathon','design','research','business','social_impact','skills'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.sponsored_challenges add constraint sponsored_challenge_team_size_chk check (min_team_size>=1 and max_team_size>=min_team_size and max_team_size<=20);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.sponsored_challenges add constraint sponsored_challenge_max_participants_chk check (max_participants is null or max_participants>=1);
exception when duplicate_object then null; end $$;

alter table public.challenge_participants
  add column if not exists status text not null default 'active',
  add column if not exists team_id uuid,
  add column if not exists withdrawn_at timestamptz;
do $$ begin alter table public.challenge_participants add constraint challenge_participant_status_chk check (status in ('active','withdrawn','disqualified','completed')); exception when duplicate_object then null; end $$;

alter table public.challenge_submissions
  add column if not exists team_id uuid,
  add column if not exists title text,
  add column if not exists description text,
  add column if not exists submission_text text,
  add column if not exists attachment_path text,
  add column if not exists status text not null default 'submitted',
  add column if not exists final_score numeric,
  add column if not exists review_count integer not null default 0,
  add column if not exists updated_at timestamptz not null default now();
do $$ begin alter table public.challenge_submissions add constraint challenge_submission_status_chk check (status in ('draft','submitted','under_review','finalist','winner','rejected','withdrawn')); exception when duplicate_object then null; end $$;

create table if not exists public.challenge_teams (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.sponsored_challenges(id) on delete cascade,
  name text not null,
  captain_id uuid not null references public.profiles(id) on delete cascade,
  join_code text not null unique default upper(substr(md5(gen_random_uuid()::text),1,10)),
  status text not null default 'active' check (status in ('active','locked','withdrawn','disqualified')),
  created_at timestamptz not null default now(),
  unique(challenge_id,name)
);

create table if not exists public.challenge_team_members (
  team_id uuid not null references public.challenge_teams(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  member_role text not null default 'member' check (member_role in ('captain','member')),
  joined_at timestamptz not null default now(),
  primary key(team_id,user_id)
);

create table if not exists public.challenge_judges (
  challenge_id uuid not null references public.sponsored_challenges(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  assigned_by uuid references public.profiles(id) on delete set null,
  assigned_at timestamptz not null default now(),
  primary key(challenge_id,user_id)
);

create table if not exists public.challenge_reviews (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.challenge_submissions(id) on delete cascade,
  judge_id uuid not null references public.profiles(id) on delete cascade,
  scores jsonb not null default '{}'::jsonb,
  total_score numeric not null check (total_score>=0 and total_score<=100),
  feedback text,
  recommendation text check (recommendation is null or recommendation in ('advance','hold','reject','winner')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(submission_id,judge_id)
);

create table if not exists public.challenge_rewards (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.sponsored_challenges(id) on delete cascade,
  submission_id uuid not null references public.challenge_submissions(id) on delete cascade,
  beneficiary_user_id uuid references public.profiles(id) on delete set null,
  beneficiary_team_id uuid references public.challenge_teams(id) on delete set null,
  amount numeric not null default 0 check (amount>=0),
  currency text not null default 'ETB',
  status text not null default 'approved' check (status in ('approved','payment_pending','paid','cancelled','failed')),
  external_ref text,
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  unique(challenge_id,submission_id)
);

-- Add circular FKs after referenced tables exist.
do $$ begin alter table public.challenge_participants add constraint challenge_participants_team_id_fkey foreign key(team_id) references public.challenge_teams(id) on delete set null; exception when duplicate_object then null; end $$;
do $$ begin alter table public.challenge_submissions add constraint challenge_submissions_team_id_fkey foreign key(team_id) references public.challenge_teams(id) on delete set null; exception when duplicate_object then null; end $$;
do $$ begin alter table public.sponsored_challenges add constraint sponsored_challenges_winner_submission_id_fkey foreign key(winner_submission_id) references public.challenge_submissions(id) on delete set null; exception when duplicate_object then null; end $$;

create index if not exists sponsored_challenges_employer_status_idx on public.sponsored_challenges(sponsor_employer_id,status,ends_at);
create index if not exists challenge_participants_user_status_idx on public.challenge_participants(user_id,status);
create index if not exists challenge_submissions_challenge_status_idx on public.challenge_submissions(challenge_id,status,final_score desc);
create index if not exists challenge_teams_challenge_idx on public.challenge_teams(challenge_id,status);
create index if not exists challenge_team_members_user_idx on public.challenge_team_members(user_id);
create index if not exists challenge_judges_user_idx on public.challenge_judges(user_id);
create index if not exists challenge_reviews_submission_idx on public.challenge_reviews(submission_id,total_score desc);
create index if not exists challenge_rewards_beneficiary_user_idx on public.challenge_rewards(beneficiary_user_id,status);

alter table public.challenge_teams enable row level security;
alter table public.challenge_team_members enable row level security;
alter table public.challenge_judges enable row level security;
alter table public.challenge_reviews enable row level security;
alter table public.challenge_rewards enable row level security;

-- Sponsor helper.
create or replace function private.has_challenge_manage_access(p_challenge_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.sponsored_challenges c where c.id=p_challenge_id and ((c.sponsor_employer_id is not null and private.has_employer_access(c.sponsor_employer_id,true)) or private.is_admin_user())); $$;

-- Replace unsafe legacy challenge RLS with controlled read/write paths.
drop policy if exists "challenges: public read" on public.sponsored_challenges;
drop policy if exists "Challenge participants self delete" on public.challenge_participants;
drop policy if exists "Challenge participants self insert" on public.challenge_participants;
drop policy if exists "Challenge participants self select" on public.challenge_participants;
drop policy if exists "Challenge participants self update" on public.challenge_participants;
drop policy if exists "Challenge submissions self delete" on public.challenge_submissions;
drop policy if exists "Challenge submissions self insert" on public.challenge_submissions;
drop policy if exists "Challenge submissions self select" on public.challenge_submissions;
drop policy if exists "Challenge submissions self update" on public.challenge_submissions;

revoke all on public.sponsored_challenges, public.challenge_participants, public.challenge_submissions, public.challenge_teams, public.challenge_team_members, public.challenge_judges, public.challenge_reviews, public.challenge_rewards from anon,authenticated;
grant select on public.sponsored_challenges to anon,authenticated;
grant select on public.challenge_participants, public.challenge_submissions, public.challenge_teams, public.challenge_team_members, public.challenge_judges, public.challenge_reviews, public.challenge_rewards to authenticated;
grant update(title,description,prize_amount_etb,starts_at,ends_at,challenge_type,category,eligibility_rules,judging_criteria,submission_requirements,team_mode,min_team_size,max_team_size,max_participants,prize_currency) on public.sponsored_challenges to authenticated;
grant insert,update(total_score,scores,feedback,recommendation,updated_at) on public.challenge_reviews to authenticated;
grant all on public.sponsored_challenges, public.challenge_participants, public.challenge_submissions, public.challenge_teams, public.challenge_team_members, public.challenge_judges, public.challenge_reviews, public.challenge_rewards to service_role;

drop policy if exists "Sponsored challenges readable" on public.sponsored_challenges;
create policy "Sponsored challenges readable" on public.sponsored_challenges for select to anon,authenticated
using (status in ('published','open','judging','completed') or (case when (select auth.uid()) is not null then private.has_challenge_manage_access(id) else false end));
drop policy if exists "Sponsors update draft challenge content" on public.sponsored_challenges;
create policy "Sponsors update draft challenge content" on public.sponsored_challenges for update to authenticated
using (private.has_challenge_manage_access(id) and status in ('draft','published','open'))
with check (private.has_challenge_manage_access(id));

drop policy if exists "Challenge participants readable" on public.challenge_participants;
create policy "Challenge participants readable" on public.challenge_participants for select to authenticated
using (user_id=(select auth.uid()) or private.has_challenge_manage_access(challenge_id) or exists(select 1 from public.sponsored_challenges c where c.id=challenge_id and c.status in ('open','judging','completed')));
drop policy if exists "Challenge submissions readable" on public.challenge_submissions;
create policy "Challenge submissions readable" on public.challenge_submissions for select to authenticated
using (user_id=(select auth.uid()) or private.has_challenge_manage_access(challenge_id) or exists(select 1 from public.challenge_judges j where j.challenge_id=challenge_id and j.user_id=(select auth.uid())) or status in ('finalist','winner'));
drop policy if exists "Challenge teams readable" on public.challenge_teams;
create policy "Challenge teams readable" on public.challenge_teams for select to authenticated
using (private.has_challenge_manage_access(challenge_id) or captain_id=(select auth.uid()) or exists(select 1 from public.challenge_team_members m where m.team_id=id and m.user_id=(select auth.uid())) or exists(select 1 from public.sponsored_challenges c where c.id=challenge_id and c.status in ('open','judging','completed')));
drop policy if exists "Challenge team members readable" on public.challenge_team_members;
create policy "Challenge team members readable" on public.challenge_team_members for select to authenticated
using (user_id=(select auth.uid()) or exists(select 1 from public.challenge_teams t where t.id=team_id and (private.has_challenge_manage_access(t.challenge_id) or t.captain_id=(select auth.uid()) or exists(select 1 from public.challenge_team_members me where me.team_id=t.id and me.user_id=(select auth.uid())))));
drop policy if exists "Challenge judges readable" on public.challenge_judges;
create policy "Challenge judges readable" on public.challenge_judges for select to authenticated
using (user_id=(select auth.uid()) or private.has_challenge_manage_access(challenge_id));
drop policy if exists "Challenge judges review submissions" on public.challenge_reviews;
create policy "Challenge judges review submissions" on public.challenge_reviews for insert to authenticated
with check (judge_id=(select auth.uid()) and exists(select 1 from public.challenge_submissions s join public.challenge_judges j on j.challenge_id=s.challenge_id where s.id=submission_id and j.user_id=(select auth.uid()) and s.status in ('submitted','under_review','finalist')));
drop policy if exists "Challenge judges update own reviews" on public.challenge_reviews;
create policy "Challenge judges update own reviews" on public.challenge_reviews for update to authenticated using (judge_id=(select auth.uid())) with check (judge_id=(select auth.uid()));
drop policy if exists "Challenge reviews readable" on public.challenge_reviews;
create policy "Challenge reviews readable" on public.challenge_reviews for select to authenticated
using (judge_id=(select auth.uid()) or exists(select 1 from public.challenge_submissions s where s.id=submission_id and (s.user_id=(select auth.uid()) or private.has_challenge_manage_access(s.challenge_id))));
drop policy if exists "Challenge rewards readable" on public.challenge_rewards;
create policy "Challenge rewards readable" on public.challenge_rewards for select to authenticated
using (beneficiary_user_id=(select auth.uid()) or (beneficiary_team_id is not null and exists(select 1 from public.challenge_team_members m where m.team_id=beneficiary_team_id and m.user_id=(select auth.uid()))) or private.has_challenge_manage_access(challenge_id));

-- Server-managed fields on challenge content.
create or replace function private.protect_sponsored_challenge_fields()
returns trigger language plpgsql security definer set search_path=''
as $$ begin
  if (select auth.uid()) is not null and not private.is_admin_user() then
    if new.sponsor_employer_id is distinct from old.sponsor_employer_id or new.created_by is distinct from old.created_by or new.status is distinct from old.status or new.published_at is distinct from old.published_at or new.winner_submission_id is distinct from old.winner_submission_id then
      raise exception 'challenge ownership and lifecycle fields are server managed';
    end if;
  end if;
  new.updated_at:=now(); return new;
end $$;
drop trigger if exists trg_protect_sponsored_challenge_fields on public.sponsored_challenges;
create trigger trg_protect_sponsored_challenge_fields before update on public.sponsored_challenges for each row execute function private.protect_sponsored_challenge_fields();

create or replace function private.create_sponsored_challenge(p_employer_id uuid,p_title text,p_description text,p_challenge_type text,p_category public.launch_category,p_prize numeric,p_starts_at timestamptz,p_ends_at timestamptz,p_team_mode boolean,p_min_team int,p_max_team int)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_id uuid; v_name text; begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if not private.has_employer_access(p_employer_id,true) and not private.is_admin_user() then raise exception 'employer write access required'; end if;
  if p_ends_at is not null and p_starts_at is not null and p_ends_at<=p_starts_at then raise exception 'challenge end must be after start'; end if;
  select company_name into v_name from public.employers where id=p_employer_id;
  insert into public.sponsored_challenges(sponsor_name,title,description,prize_amount_etb,starts_at,ends_at,sponsor_employer_id,created_by,challenge_type,category,status,team_mode,min_team_size,max_team_size)
  values(coalesce(v_name,'Mela Partner'),p_title,p_description,p_prize,p_starts_at,p_ends_at,p_employer_id,v_uid,p_challenge_type,p_category,'draft',coalesce(p_team_mode,false),case when p_team_mode then greatest(1,coalesce(p_min_team,2)) else 1 end,case when p_team_mode then greatest(coalesce(p_max_team,5),coalesce(p_min_team,2)) else 1 end)
  returning id into v_id;
  return v_id;
end $$;
create or replace function public.create_sponsored_challenge(p_employer_id uuid,p_title text,p_description text,p_challenge_type text default 'innovation',p_category public.launch_category default null,p_prize numeric default null,p_starts_at timestamptz default null,p_ends_at timestamptz default null,p_team_mode boolean default false,p_min_team int default 1,p_max_team int default 1)
returns uuid language sql security invoker set search_path='' as $$ select private.create_sponsored_challenge(p_employer_id,p_title,p_description,p_challenge_type,p_category,p_prize,p_starts_at,p_ends_at,p_team_mode,p_min_team,p_max_team); $$;

create or replace function private.publish_sponsored_challenge(p_challenge_id uuid)
returns public.sponsored_challenges language plpgsql security definer set search_path=''
as $$ declare v public.sponsored_challenges; begin
  if not private.has_challenge_manage_access(p_challenge_id) then raise exception 'challenge management access required'; end if;
  update public.sponsored_challenges set status=case when starts_at is null or starts_at<=now() then 'open' else 'published' end,published_at=coalesce(published_at,now()),updated_at=now() where id=p_challenge_id and status in ('draft','published') returning * into v;
  if v.id is null then raise exception 'challenge cannot be published from current state'; end if; return v;
end $$;
create or replace function public.publish_sponsored_challenge(p_challenge_id uuid) returns public.sponsored_challenges language sql security invoker set search_path='' as $$ select private.publish_sponsored_challenge(p_challenge_id); $$;

create or replace function private.join_sponsored_challenge(p_challenge_id uuid)
returns public.challenge_participants language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_c public.sponsored_challenges; v public.challenge_participants; begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_c from public.sponsored_challenges where id=p_challenge_id for update;
  if v_c.id is null or v_c.status not in ('published','open') or (v_c.starts_at is not null and now()<v_c.starts_at-interval '30 days') or (v_c.ends_at is not null and now()>=v_c.ends_at) then raise exception 'challenge is not open for participation'; end if;
  if v_c.max_participants is not null and (select count(*) from public.challenge_participants where challenge_id=p_challenge_id and status='active')>=v_c.max_participants then raise exception 'challenge is full'; end if;
  insert into public.challenge_participants(challenge_id,user_id,status) values(p_challenge_id,v_uid,'active')
  on conflict(challenge_id,user_id) do update set status='active',withdrawn_at=null returning * into v;
  return v;
end $$;
create or replace function public.join_sponsored_challenge(p_challenge_id uuid) returns public.challenge_participants language sql security invoker set search_path='' as $$ select private.join_sponsored_challenge(p_challenge_id); $$;

create or replace function private.create_challenge_team(p_challenge_id uuid,p_name text)
returns public.challenge_teams language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_c public.sponsored_challenges; v public.challenge_teams; begin
  select * into v_c from public.sponsored_challenges where id=p_challenge_id;
  if v_uid is null or v_c.id is null or not v_c.team_mode then raise exception 'team challenge required'; end if;
  if not exists(select 1 from public.challenge_participants where challenge_id=p_challenge_id and user_id=v_uid and status='active') then perform private.join_sponsored_challenge(p_challenge_id); end if;
  insert into public.challenge_teams(challenge_id,name,captain_id) values(p_challenge_id,p_name,v_uid) returning * into v;
  insert into public.challenge_team_members(team_id,user_id,member_role) values(v.id,v_uid,'captain');
  update public.challenge_participants set team_id=v.id where challenge_id=p_challenge_id and user_id=v_uid;
  return v;
end $$;
create or replace function public.create_challenge_team(p_challenge_id uuid,p_name text) returns public.challenge_teams language sql security invoker set search_path='' as $$ select private.create_challenge_team(p_challenge_id,p_name); $$;

create or replace function private.join_challenge_team(p_join_code text)
returns public.challenge_teams language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_t public.challenge_teams; v_c public.sponsored_challenges; begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_t from public.challenge_teams where join_code=upper(trim(p_join_code)) and status='active' for update;
  if v_t.id is null then raise exception 'team not found'; end if;
  select * into v_c from public.sponsored_challenges where id=v_t.challenge_id;
  if v_c.status not in ('published','open') or (select count(*) from public.challenge_team_members where team_id=v_t.id)>=v_c.max_team_size then raise exception 'team cannot accept more members'; end if;
  if not exists(select 1 from public.challenge_participants where challenge_id=v_t.challenge_id and user_id=v_uid and status='active') then perform private.join_sponsored_challenge(v_t.challenge_id); end if;
  insert into public.challenge_team_members(team_id,user_id) values(v_t.id,v_uid) on conflict do nothing;
  update public.challenge_participants set team_id=v_t.id where challenge_id=v_t.challenge_id and user_id=v_uid;
  return v_t;
end $$;
create or replace function public.join_challenge_team(p_join_code text) returns public.challenge_teams language sql security invoker set search_path='' as $$ select private.join_challenge_team(p_join_code); $$;

create or replace function private.submit_challenge_entry(p_challenge_id uuid,p_title text,p_submission_text text,p_submission_url text,p_attachment_path text)
returns public.challenge_submissions language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_c public.sponsored_challenges; v_team uuid; v public.challenge_submissions; begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_c from public.sponsored_challenges where id=p_challenge_id;
  if v_c.id is null or v_c.status not in ('published','open') or (v_c.ends_at is not null and now()>v_c.ends_at) then raise exception 'challenge submissions are closed'; end if;
  select team_id into v_team from public.challenge_participants where challenge_id=p_challenge_id and user_id=v_uid and status='active';
  if not found then raise exception 'join the challenge before submitting'; end if;
  if v_c.team_mode and v_team is null then raise exception 'join a challenge team before submitting'; end if;
  if v_c.team_mode and exists(select 1 from public.challenge_submissions s where s.challenge_id=p_challenge_id and s.team_id=v_team and s.status<>'withdrawn') then raise exception 'team already has a submission'; end if;
  if not v_c.team_mode and exists(select 1 from public.challenge_submissions s where s.challenge_id=p_challenge_id and s.user_id=v_uid and s.status<>'withdrawn') then
    update public.challenge_submissions set title=p_title,submission_text=p_submission_text,submission_url=p_submission_url,attachment_path=p_attachment_path,status='submitted',submitted_at=now(),updated_at=now(),score=null,rank=null,final_score=null,review_count=0 where challenge_id=p_challenge_id and user_id=v_uid and status<>'withdrawn' returning * into v;
  else
    insert into public.challenge_submissions(challenge_id,user_id,team_id,title,submission_text,submission_url,attachment_path,status) values(p_challenge_id,v_uid,v_team,p_title,p_submission_text,p_submission_url,p_attachment_path,'submitted') returning * into v;
  end if;
  update public.sponsored_challenges set status=case when status='published' and (starts_at is null or starts_at<=now()) then 'open' else status end,updated_at=now() where id=p_challenge_id;
  return v;
end $$;
create or replace function public.submit_challenge_entry(p_challenge_id uuid,p_title text,p_submission_text text default null,p_submission_url text default null,p_attachment_path text default null) returns public.challenge_submissions language sql security invoker set search_path='' as $$ select private.submit_challenge_entry(p_challenge_id,p_title,p_submission_text,p_submission_url,p_attachment_path); $$;

create or replace function private.finalize_sponsored_challenge(p_challenge_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_winner uuid; v_user uuid; v_team uuid; v_prize numeric; v_currency text; r record; begin
  if not private.has_challenge_manage_access(p_challenge_id) then raise exception 'challenge management access required'; end if;
  if not exists(select 1 from public.challenge_submissions where challenge_id=p_challenge_id and status in ('submitted','under_review','finalist')) then raise exception 'no eligible submissions'; end if;
  update public.sponsored_challenges set status='judging',updated_at=now() where id=p_challenge_id;
  for r in select s.id,coalesce(avg(cr.total_score),0)::numeric as avg_score,count(cr.id)::int as rc from public.challenge_submissions s left join public.challenge_reviews cr on cr.submission_id=s.id where s.challenge_id=p_challenge_id and s.status in ('submitted','under_review','finalist') group by s.id loop
    update public.challenge_submissions set final_score=r.avg_score,score=r.avg_score,review_count=r.rc,status='under_review',updated_at=now() where id=r.id;
  end loop;
  with ranked as (select id,row_number() over(order by final_score desc nulls last,submitted_at asc) rn from public.challenge_submissions where challenge_id=p_challenge_id and status='under_review')
  update public.challenge_submissions s set rank=r.rn,status=case when r.rn=1 then 'winner' when r.rn<=3 then 'finalist' else 'rejected' end,updated_at=now() from ranked r where s.id=r.id;
  select id,user_id,team_id into v_winner,v_user,v_team from public.challenge_submissions where challenge_id=p_challenge_id and rank=1;
  select prize_amount_etb,prize_currency into v_prize,v_currency from public.sponsored_challenges where id=p_challenge_id;
  update public.sponsored_challenges set status='completed',winner_submission_id=v_winner,updated_at=now() where id=p_challenge_id;
  insert into public.challenge_rewards(challenge_id,submission_id,beneficiary_user_id,beneficiary_team_id,amount,currency,status)
  values(p_challenge_id,v_winner,case when v_team is null then v_user else null end,v_team,coalesce(v_prize,0),coalesce(v_currency,'ETB'),'approved') on conflict(challenge_id,submission_id) do nothing;
  if v_team is null then perform private.create_notification(v_user,'Challenge winner','Congratulations — your sponsored challenge submission ranked first.','challenge_submissions',v_winner);
  else
    for r in select user_id from public.challenge_team_members where team_id=v_team loop perform private.create_notification(r.user_id,'Challenge winner','Congratulations — your team ranked first in a sponsored challenge.','challenge_submissions',v_winner); end loop;
  end if;
  return v_winner;
end $$;
create or replace function public.finalize_sponsored_challenge(p_challenge_id uuid) returns uuid language sql security invoker set search_path='' as $$ select private.finalize_sponsored_challenge(p_challenge_id); $$;

-- Arena completion: generalized multi-mode competition engine.
alter table public.arena_matches
  add column if not exists title text,
  add column if not exists description text,
  add column if not exists arena_type text not null default 'quiz_battle',
  add column if not exists creator_id uuid references public.profiles(id) on delete set null,
  add column if not exists visibility text not null default 'public',
  add column if not exists assessment_id uuid references public.skill_assessments(id) on delete set null,
  add column if not exists sponsored_challenge_id uuid references public.sponsored_challenges(id) on delete set null,
  add column if not exists min_participants integer not null default 2,
  add column if not exists max_participants integer not null default 2,
  add column if not exists team_mode boolean not null default false,
  add column if not exists join_deadline timestamptz,
  add column if not exists scheduled_at timestamptz,
  add column if not exists rules jsonb not null default '{}'::jsonb,
  add column if not exists scoring_mode text not null default 'auto',
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

do $$ begin alter table public.arena_matches drop constraint if exists arena_matches_status_check; exception when undefined_object then null; end $$;
do $$ begin alter table public.arena_matches add constraint arena_match_status_chk check(status in ('draft','open','ready','live','completed','cancelled')); exception when duplicate_object then null; end $$;
do $$ begin alter table public.arena_matches add constraint arena_match_type_chk check(arena_type in ('quiz_battle','speed_quiz','interview_practice','case_sprint','team_battle','skill_sprint','employer_challenge')); exception when duplicate_object then null; end $$;
do $$ begin alter table public.arena_matches add constraint arena_match_visibility_chk check(visibility in ('public','private','invite')); exception when duplicate_object then null; end $$;
do $$ begin alter table public.arena_matches add constraint arena_match_scoring_chk check(scoring_mode in ('auto','judge','hybrid')); exception when duplicate_object then null; end $$;
do $$ begin alter table public.arena_matches add constraint arena_match_participant_chk check(min_participants>=1 and max_participants>=min_participants and max_participants<=100); exception when duplicate_object then null; end $$;

alter table public.arena_participants
  add column if not exists joined_at timestamptz not null default now(),
  add column if not exists status text not null default 'joined',
  add column if not exists ready boolean not null default false,
  add column if not exists team_id uuid,
  add column if not exists finished_at timestamptz;
do $$ begin alter table public.arena_participants add constraint arena_participant_status_chk check(status in ('joined','active','finished','withdrawn','disqualified')); exception when duplicate_object then null; end $$;

create table if not exists public.arena_teams (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.arena_matches(id) on delete cascade,
  name text not null,
  captain_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(match_id,name)
);
create table if not exists public.arena_team_members (
  team_id uuid not null references public.arena_teams(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key(team_id,user_id)
);
do $$ begin alter table public.arena_participants add constraint arena_participants_team_id_fkey foreign key(team_id) references public.arena_teams(id) on delete set null; exception when duplicate_object then null; end $$;

create table if not exists public.arena_rounds (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.arena_matches(id) on delete cascade,
  round_order integer not null,
  round_type text not null default 'quiz' check(round_type in ('quiz','interview','case','task','presentation')),
  title text,
  prompt text,
  assessment_question_id uuid references public.assessment_questions(id) on delete set null,
  max_points numeric not null default 10 check(max_points>0),
  time_limit_seconds integer check(time_limit_seconds is null or time_limit_seconds>0),
  starts_at timestamptz,
  ends_at timestamptz,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(match_id,round_order)
);

create table if not exists public.arena_round_submissions (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.arena_rounds(id) on delete cascade,
  match_id uuid not null references public.arena_matches(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  response jsonb not null default 'null'::jsonb,
  attachment_url text,
  score numeric,
  feedback text,
  reviewed_by uuid references public.profiles(id) on delete set null,
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  unique(round_id,user_id),
  check(score is null or score>=0)
);

create table if not exists public.arena_invites (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.arena_matches(id) on delete cascade,
  invited_user_id uuid not null references public.profiles(id) on delete cascade,
  invited_by uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check(status in ('pending','accepted','declined','expired')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  unique(match_id,invited_user_id)
);

create index if not exists arena_matches_type_status_idx on public.arena_matches(arena_type,status,scheduled_at);
create index if not exists arena_matches_creator_idx on public.arena_matches(creator_id,created_at desc);
create index if not exists arena_participants_user_status_idx on public.arena_participants(user_id,status);
create index if not exists arena_rounds_match_idx on public.arena_rounds(match_id,round_order);
create index if not exists arena_round_submissions_user_idx on public.arena_round_submissions(user_id,submitted_at desc);
create index if not exists arena_invites_user_status_idx on public.arena_invites(invited_user_id,status);

alter table public.arena_teams enable row level security;
alter table public.arena_team_members enable row level security;
alter table public.arena_rounds enable row level security;
alter table public.arena_round_submissions enable row level security;
alter table public.arena_invites enable row level security;

-- Remove legacy open write/read policies and make arena access scoped.
drop policy if exists "arena_matches: public read" on public.arena_matches;
drop policy if exists "Arena participants self delete" on public.arena_participants;
drop policy if exists "Arena participants self insert" on public.arena_participants;
drop policy if exists "arena_participants: public read for leaderboard" on public.arena_participants;
drop policy if exists "Arena participants self update" on public.arena_participants;

revoke all on public.arena_matches,public.arena_participants,public.arena_teams,public.arena_team_members,public.arena_rounds,public.arena_round_submissions,public.arena_invites from anon,authenticated;
grant select on public.arena_matches,public.arena_participants,public.arena_teams,public.arena_team_members,public.arena_rounds,public.arena_round_submissions,public.arena_invites to authenticated;
grant select on public.arena_matches,public.arena_participants to anon;
grant insert,update,delete on public.arena_rounds to authenticated;
grant insert,update on public.arena_invites to authenticated;
grant all on public.arena_matches,public.arena_participants,public.arena_teams,public.arena_team_members,public.arena_rounds,public.arena_round_submissions,public.arena_invites to service_role;

drop policy if exists "Arena matches readable" on public.arena_matches;
create policy "Arena matches readable" on public.arena_matches for select to anon,authenticated
using (visibility='public' and status in ('open','ready','live','completed') or (case when (select auth.uid()) is not null then creator_id=(select auth.uid()) or exists(select 1 from public.arena_participants p where p.match_id=id and p.user_id=(select auth.uid())) or exists(select 1 from public.arena_invites i where i.match_id=id and i.invited_user_id=(select auth.uid())) or private.is_admin_user() else false end));
drop policy if exists "Arena participants readable" on public.arena_participants;
create policy "Arena participants readable" on public.arena_participants for select to anon,authenticated
using (exists(select 1 from public.arena_matches m where m.id=match_id and (m.visibility='public' and m.status in ('open','ready','live','completed') or (case when (select auth.uid()) is not null then m.creator_id=(select auth.uid()) or user_id=(select auth.uid()) or exists(select 1 from public.arena_participants me where me.match_id=m.id and me.user_id=(select auth.uid())) or private.is_admin_user() else false end))));
drop policy if exists "Arena rounds readable" on public.arena_rounds;
create policy "Arena rounds readable" on public.arena_rounds for select to authenticated
using (exists(select 1 from public.arena_matches m where m.id=match_id and (m.creator_id=(select auth.uid()) or exists(select 1 from public.arena_participants p where p.match_id=m.id and p.user_id=(select auth.uid())) or private.is_admin_user())));
drop policy if exists "Arena creator manages rounds" on public.arena_rounds;
create policy "Arena creator manages rounds" on public.arena_rounds for all to authenticated
using (exists(select 1 from public.arena_matches m where m.id=match_id and (m.creator_id=(select auth.uid()) or private.is_admin_user()) and m.status in ('draft','open')))
with check (exists(select 1 from public.arena_matches m where m.id=match_id and (m.creator_id=(select auth.uid()) or private.is_admin_user()) and m.status in ('draft','open')));
drop policy if exists "Arena submissions readable" on public.arena_round_submissions;
create policy "Arena submissions readable" on public.arena_round_submissions for select to authenticated
using (user_id=(select auth.uid()) or exists(select 1 from public.arena_matches m where m.id=match_id and (m.creator_id=(select auth.uid()) or private.is_admin_user())));
drop policy if exists "Arena invites readable" on public.arena_invites;
create policy "Arena invites readable" on public.arena_invites for select to authenticated
using (invited_user_id=(select auth.uid()) or invited_by=(select auth.uid()) or exists(select 1 from public.arena_matches m where m.id=match_id and m.creator_id=(select auth.uid())));
drop policy if exists "Arena creator sends invites" on public.arena_invites;
create policy "Arena creator sends invites" on public.arena_invites for insert to authenticated
with check (invited_by=(select auth.uid()) and exists(select 1 from public.arena_matches m where m.id=match_id and (m.creator_id=(select auth.uid()) or private.is_admin_user())));
drop policy if exists "Arena invitee responds" on public.arena_invites;
create policy "Arena invitee responds" on public.arena_invites for update to authenticated using (invited_user_id=(select auth.uid()) and status='pending') with check (invited_user_id=(select auth.uid()) and status in ('accepted','declined'));

drop policy if exists "Arena teams readable" on public.arena_teams;
create policy "Arena teams readable" on public.arena_teams for select to authenticated using (captain_id=(select auth.uid()) or exists(select 1 from public.arena_team_members tm where tm.team_id=id and tm.user_id=(select auth.uid())) or exists(select 1 from public.arena_matches m where m.id=match_id and (m.visibility='public' or m.creator_id=(select auth.uid()) or private.is_admin_user())));
drop policy if exists "Arena team members readable" on public.arena_team_members;
create policy "Arena team members readable" on public.arena_team_members for select to authenticated using (user_id=(select auth.uid()) or exists(select 1 from public.arena_teams t where t.id=team_id and (t.captain_id=(select auth.uid()) or exists(select 1 from public.arena_team_members me where me.team_id=t.id and me.user_id=(select auth.uid())))));

create or replace function private.create_arena(p_title text,p_arena_type text,p_visibility text,p_assessment_id uuid,p_max_participants int,p_team_mode boolean,p_scheduled_at timestamptz)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_id uuid; begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_arena_type not in ('quiz_battle','speed_quiz','interview_practice','case_sprint','team_battle','skill_sprint','employer_challenge') then raise exception 'unsupported arena type'; end if;
  insert into public.arena_matches(title,arena_type,creator_id,visibility,assessment_id,max_participants,min_participants,team_mode,scheduled_at,status,scoring_mode)
  values(p_title,p_arena_type,v_uid,coalesce(p_visibility,'public'),p_assessment_id,greatest(1,least(coalesce(p_max_participants,2),100)),case when coalesce(p_max_participants,2)=1 then 1 else 2 end,coalesce(p_team_mode,false),p_scheduled_at,'open',case when p_arena_type in ('quiz_battle','speed_quiz') then 'auto' else 'judge' end)
  returning id into v_id;
  insert into public.arena_participants(match_id,user_id,status,ready) values(v_id,v_uid,'joined',false);
  return v_id;
end $$;
create or replace function public.create_arena(p_title text,p_arena_type text default 'quiz_battle',p_visibility text default 'public',p_assessment_id uuid default null,p_max_participants int default 2,p_team_mode boolean default false,p_scheduled_at timestamptz default null) returns uuid language sql security invoker set search_path='' as $$ select private.create_arena(p_title,p_arena_type,p_visibility,p_assessment_id,p_max_participants,p_team_mode,p_scheduled_at); $$;

create or replace function private.join_arena(p_match_id uuid)
returns public.arena_participants language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_m public.arena_matches; v public.arena_participants; begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_m from public.arena_matches where id=p_match_id for update;
  if v_m.id is null or v_m.status not in ('open','ready') then raise exception 'arena is not joinable'; end if;
  if v_m.join_deadline is not null and now()>v_m.join_deadline then raise exception 'arena join deadline passed'; end if;
  if v_m.visibility in ('private','invite') and v_m.creator_id<>v_uid and not exists(select 1 from public.arena_invites where match_id=p_match_id and invited_user_id=v_uid and status in ('pending','accepted')) then raise exception 'arena invitation required'; end if;
  if (select count(*) from public.arena_participants where match_id=p_match_id and status in ('joined','active','finished'))>=v_m.max_participants then raise exception 'arena is full'; end if;
  insert into public.arena_participants(match_id,user_id,status,ready) values(p_match_id,v_uid,'joined',false)
  on conflict(match_id,user_id) do update set status='joined' returning * into v;
  update public.arena_invites set status='accepted',responded_at=now() where match_id=p_match_id and invited_user_id=v_uid and status='pending';
  return v;
end $$;
create or replace function public.join_arena(p_match_id uuid) returns public.arena_participants language sql security invoker set search_path='' as $$ select private.join_arena(p_match_id); $$;

create or replace function private.set_arena_ready(p_match_id uuid,p_ready boolean)
returns void language plpgsql security definer set search_path=''
as $$ begin
  if not exists(select 1 from public.arena_participants where match_id=p_match_id and user_id=(select auth.uid()) and status='joined') then raise exception 'arena participant required'; end if;
  update public.arena_participants set ready=p_ready where match_id=p_match_id and user_id=(select auth.uid());
  update public.arena_matches m set status=case when (select count(*) from public.arena_participants p where p.match_id=m.id and p.status='joined')>=m.min_participants and not exists(select 1 from public.arena_participants p where p.match_id=m.id and p.status='joined' and p.ready=false) then 'ready' else 'open' end,updated_at=now() where id=p_match_id and status in ('open','ready');
end $$;
create or replace function public.set_arena_ready(p_match_id uuid,p_ready boolean default true) returns void language sql security invoker set search_path='' as $$ select private.set_arena_ready(p_match_id,p_ready); $$;

create or replace function private.start_arena(p_match_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ declare v_m public.arena_matches; begin
  select * into v_m from public.arena_matches where id=p_match_id for update;
  if v_m.id is null or (v_m.creator_id<>(select auth.uid()) and not private.is_admin_user()) then raise exception 'arena creator access required'; end if;
  if v_m.status not in ('open','ready') then raise exception 'arena cannot start'; end if;
  if (select count(*) from public.arena_participants where match_id=p_match_id and status='joined')<v_m.min_participants then raise exception 'not enough participants'; end if;
  if v_m.assessment_id is not null and v_m.arena_type in ('quiz_battle','speed_quiz') and not exists(select 1 from public.arena_rounds where match_id=p_match_id) then
    insert into public.arena_rounds(match_id,round_order,round_type,title,prompt,assessment_question_id,max_points,time_limit_seconds)
    select p_match_id,row_number() over(order by q.question_order),'quiz','Question '||row_number() over(order by q.question_order),q.prompt,q.id,q.points,case when v_m.arena_type='speed_quiz' then 45 else 90 end
    from public.assessment_questions q where q.assessment_id=v_m.assessment_id and q.active=true order by q.question_order limit 20;
  end if;
  if not exists(select 1 from public.arena_rounds where match_id=p_match_id) then raise exception 'arena needs at least one round'; end if;
  update public.arena_matches set status='live',started_at=now(),updated_at=now() where id=p_match_id;
  update public.arena_participants set status='active' where match_id=p_match_id and status='joined';
end $$;
create or replace function public.start_arena(p_match_id uuid) returns void language sql security invoker set search_path='' as $$ select private.start_arena(p_match_id); $$;

create or replace function private.submit_arena_round(p_round_id uuid,p_response jsonb,p_attachment_url text)
returns public.arena_round_submissions language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_r public.arena_rounds; v_m public.arena_matches; v_correct jsonb; v_score numeric; v public.arena_round_submissions; begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select r.* into v_r from public.arena_rounds r where r.id=p_round_id;
  if v_r.id is null then raise exception 'arena round not found'; end if;
  select * into v_m from public.arena_matches where id=v_r.match_id;
  if v_m.status<>'live' or not exists(select 1 from public.arena_participants p where p.match_id=v_m.id and p.user_id=v_uid and p.status='active') then raise exception 'active arena participation required'; end if;
  if v_r.starts_at is not null and now()<v_r.starts_at then raise exception 'round has not started'; end if;
  if v_r.ends_at is not null and now()>v_r.ends_at then raise exception 'round is closed'; end if;
  v_score:=null;
  if v_r.round_type='quiz' and v_r.assessment_question_id is not null then
    select correct_answer into v_correct from private.assessment_answer_keys where question_id=v_r.assessment_question_id;
    if v_correct is not null then v_score:=case when p_response=v_correct then v_r.max_points else 0 end; end if;
  end if;
  insert into public.arena_round_submissions(round_id,match_id,user_id,response,attachment_url,score)
  values(p_round_id,v_m.id,v_uid,coalesce(p_response,'null'::jsonb),p_attachment_url,v_score)
  on conflict(round_id,user_id) do update set response=excluded.response,attachment_url=excluded.attachment_url,score=excluded.score,submitted_at=now(),feedback=null,reviewed_by=null,reviewed_at=null
  returning * into v;
  update public.arena_participants p set score=coalesce((select sum(coalesce(s.score,0))::int from public.arena_round_submissions s where s.match_id=v_m.id and s.user_id=v_uid),0) where p.match_id=v_m.id and p.user_id=v_uid;
  return v;
end $$;
create or replace function public.submit_arena_round(p_round_id uuid,p_response jsonb,p_attachment_url text default null) returns public.arena_round_submissions language sql security invoker set search_path='' as $$ select private.submit_arena_round(p_round_id,p_response,p_attachment_url); $$;

create or replace function private.review_arena_submission(p_submission_id uuid,p_score numeric,p_feedback text)
returns public.arena_round_submissions language plpgsql security definer set search_path=''
as $$ declare v public.arena_round_submissions; v_match uuid; v_max numeric; begin
  select s.match_id,r.max_points into v_match,v_max from public.arena_round_submissions s join public.arena_rounds r on r.id=s.round_id where s.id=p_submission_id;
  if v_match is null or not exists(select 1 from public.arena_matches m where m.id=v_match and (m.creator_id=(select auth.uid()) or private.is_admin_user())) then raise exception 'arena reviewer access required'; end if;
  if p_score<0 or p_score>v_max then raise exception 'score outside round range'; end if;
  update public.arena_round_submissions set score=p_score,feedback=p_feedback,reviewed_by=(select auth.uid()),reviewed_at=now() where id=p_submission_id returning * into v;
  update public.arena_participants p set score=coalesce((select sum(coalesce(s.score,0))::int from public.arena_round_submissions s where s.match_id=v_match and s.user_id=p.user_id),0) where p.match_id=v_match;
  return v;
end $$;
create or replace function public.review_arena_submission(p_submission_id uuid,p_score numeric,p_feedback text default null) returns public.arena_round_submissions language sql security invoker set search_path='' as $$ select private.review_arena_submission(p_submission_id,p_score,p_feedback); $$;

create or replace function private.finish_arena(p_match_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ begin
  if not exists(select 1 from public.arena_matches m where m.id=p_match_id and (m.creator_id=(select auth.uid()) or private.is_admin_user())) then raise exception 'arena creator access required'; end if;
  with ranked as (select user_id,row_number() over(order by score desc,joined_at asc) rn from public.arena_participants where match_id=p_match_id and status in ('active','finished'))
  update public.arena_participants p set placement=r.rn,status='finished',finished_at=coalesce(finished_at,now()) from ranked r where p.match_id=p_match_id and p.user_id=r.user_id;
  update public.arena_matches set status='completed',ended_at=now(),updated_at=now() where id=p_match_id and status in ('live','ready');
end $$;
create or replace function public.finish_arena(p_match_id uuid) returns void language sql security invoker set search_path='' as $$ select private.finish_arena(p_match_id); $$;

-- Function grants: public wrappers and private implementations.
do $$ declare r record; begin
  for r in select n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public' and p.proname in ('create_sponsored_challenge','publish_sponsored_challenge','join_sponsored_challenge','create_challenge_team','join_challenge_team','submit_challenge_entry','finalize_sponsored_challenge','create_arena','join_arena','set_arena_ready','start_arena','submit_arena_round','review_arena_submission','finish_arena')) or (n.nspname='private' and p.proname in ('create_sponsored_challenge','publish_sponsored_challenge','join_sponsored_challenge','create_challenge_team','join_challenge_team','submit_challenge_entry','finalize_sponsored_challenge','create_arena','join_arena','set_arena_ready','start_arena','submit_arena_round','review_arena_submission','finish_arena')) loop
    execute format('revoke all on function %I.%I(%s) from public,anon',r.nspname,r.proname,r.args);
    execute format('grant execute on function %I.%I(%s) to authenticated,service_role',r.nspname,r.proname,r.args);
  end loop;
end $$;

;

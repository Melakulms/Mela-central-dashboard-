-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260816062614
alter table public.profiles
  add column if not exists account_status text not null default 'pending_verification',
  add column if not exists profile_completion smallint not null default 0,
  add column if not exists onboarding_step text not null default 'verify',
  add column if not exists role_selected_at timestamptz,
  add column if not exists deleted_at timestamptz;

alter table public.profiles drop constraint if exists profiles_account_status_check;
alter table public.profiles add constraint profiles_account_status_check check (account_status in ('pending_verification','active','suspended','banned','deleted'));
alter table public.profiles drop constraint if exists profiles_profile_completion_check;
alter table public.profiles add constraint profiles_profile_completion_check check (profile_completion between 0 and 100);

update public.profiles
set account_status=case when email_verified or phone_verified then 'active' else 'pending_verification' end
where account_status='pending_verification';

create table if not exists public.student_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  date_of_birth date,
  gender text,
  school_name text,
  city text,
  region text,
  subjects text[] not null default '{}',
  learning_interests text[] not null default '{}',
  skills text[] not null default '{}',
  goals text[] not null default '{}',
  preferred_learning_areas text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.parent_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  occupation text,
  city text,
  region text,
  interests text[] not null default '{}',
  skills text[] not null default '{}',
  employment_preferences text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.teacher_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  qualification text,
  subjects_taught text[] not null default '{}',
  grade_levels text[] not null default '{}',
  teaching_experience_years integer not null default 0 check (teaching_experience_years >= 0),
  institution text,
  skills text[] not null default '{}',
  certifications text[] not null default '{}',
  biography text,
  teaching_interests text[] not null default '{}',
  content_creator_status text not null default 'inactive' check (content_creator_status in ('inactive','pending','approved','suspended')),
  availability text,
  verification_status text not null default 'pending' check (verification_status in ('pending','approved','rejected','suspended')),
  verified_by uuid references public.profiles(id),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.company_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  employer_id uuid unique references public.employers(id) on delete set null,
  authorized_representative text,
  representative_title text,
  business_registration_number text,
  verification_status text not null default 'pending' check (verification_status in ('pending','approved','rejected','suspended')),
  verified_by uuid references public.profiles(id),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  plan_key text not null unique,
  name text not null,
  tier text not null check (tier in ('free','premium')),
  price_minor integer not null default 0 check (price_minor >= 0),
  currency text not null default 'ETB',
  billing_period_days integer check (billing_period_days is null or billing_period_days > 0),
  active boolean not null default true,
  features jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.subscription_plans(plan_key,name,tier,price_minor,currency,billing_period_days,features)
values
 ('free','Mela Free','free',0,'ETB',null,jsonb_build_object('basic_practice',true,'basic_progress',true)),
 ('premium_monthly','Mela Premium Monthly','premium',0,'ETB',30,jsonb_build_object('full_practice',true,'advanced_progress',true,'jobs',true,'scholarships',true,'duels',true,'earnings',true))
on conflict (plan_key) do nothing;

create table if not exists public.user_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  plan_id uuid not null references public.subscription_plans(id),
  status text not null check (status in ('free','premium_pending','premium_active','premium_expired','cancelled','payment_failed')),
  starts_at timestamptz,
  expires_at timestamptz,
  cancelled_at timestamptz,
  source_payment_attempt_id uuid references public.mela_learning_payment_attempts(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists user_subscriptions_one_current_idx on public.user_subscriptions(user_id) where status in ('free','premium_pending','premium_active');
create index if not exists user_subscriptions_user_status_idx on public.user_subscriptions(user_id,status,expires_at);

insert into public.user_subscriptions(user_id,plan_id,status,starts_at)
select p.id,sp.id,'free',now()
from public.profiles p cross join public.subscription_plans sp
where sp.plan_key='free'
  and not exists(select 1 from public.user_subscriptions us where us.user_id=p.id and us.status in ('free','premium_pending','premium_active'));

create table if not exists public.parent_link_invites (
  id uuid primary key default gen_random_uuid(),
  learner_id uuid not null references public.profiles(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  redeemed_by uuid references public.profiles(id),
  redeemed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists parent_link_invites_learner_idx on public.parent_link_invites(learner_id,expires_at);

alter table public.opportunities add column if not exists moderation_status text not null default 'approved';
alter table public.opportunities add column if not exists moderation_notes text;
alter table public.opportunities add column if not exists reviewed_by uuid references public.profiles(id);
alter table public.opportunities add column if not exists reviewed_at timestamptz;
alter table public.opportunities drop constraint if exists opportunities_moderation_status_check;
alter table public.opportunities add constraint opportunities_moderation_status_check check (moderation_status in ('pending_review','approved','rejected','suspended','archived'));
create index if not exists opportunities_moderation_idx on public.opportunities(moderation_status,opportunity_type,deadline);

create or replace function private.has_verified_guardian_link(p_guardian uuid,p_learner uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.guardian_relationships g where g.guardian_user_id=p_guardian and g.learner_id=p_learner and g.status='verified');
$$;
revoke all on function private.has_verified_guardian_link(uuid,uuid) from public,anon,authenticated;

create or replace function private.current_account_can_access()
returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select p.account_status='active' and (p.email_verified or p.phone_verified) from public.profiles p where p.id=(select auth.uid())),false);
$$;
revoke all on function private.current_account_can_access() from public,anon;
grant execute on function private.current_account_can_access() to authenticated;

create or replace function private.current_user_is_premium()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
   select 1 from public.user_subscriptions us join public.subscription_plans sp on sp.id=us.plan_id
   where us.user_id=(select auth.uid()) and sp.tier='premium' and us.status='premium_active'
     and (us.expires_at is null or us.expires_at>now())
 );
$$;
revoke all on function private.current_user_is_premium() from public,anon;
grant execute on function private.current_user_is_premium() to authenticated;

create or replace function public.get_my_access_context_v35()
returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object(
   'user_id',p.id,'role',p.role,'account_status',p.account_status,
   'verified',(p.email_verified or p.phone_verified),
   'profile_completion',p.profile_completion,'onboarding_step',p.onboarding_step,
   'subscription',coalesce((select jsonb_build_object('status',us.status,'tier',sp.tier,'plan_key',sp.plan_key,'expires_at',us.expires_at)
      from public.user_subscriptions us join public.subscription_plans sp on sp.id=us.plan_id
      where us.user_id=p.id and us.status in ('free','premium_pending','premium_active') order by us.created_at desc limit 1),jsonb_build_object('status','free','tier','free'))
 ) from public.profiles p where p.id=(select auth.uid());
$$;
revoke all on function public.get_my_access_context_v35() from public,anon;
grant execute on function public.get_my_access_context_v35() to authenticated;

create or replace function private.select_account_type_v35(p_role public.user_role)
returns public.profiles language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_row public.profiles%rowtype;
begin
 if v_uid is null then raise exception 'authentication required'; end if;
 if p_role not in ('student'::public.user_role,'parent'::public.user_role,'teacher'::public.user_role,'company'::public.user_role) then raise exception 'unsupported account type'; end if;
 select * into v_row from public.profiles where id=v_uid for update;
 if not found then raise exception 'profile not found'; end if;
 if not (v_row.email_verified or v_row.phone_verified) then raise exception 'account verification required'; end if;
 if v_row.role_selected_at is not null and v_row.role<>p_role then raise exception 'account type is locked; administrator review required'; end if;
 update public.profiles set role=p_role,role_selected_at=coalesce(role_selected_at,now()),account_status='active',onboarding_step='profile',updated_at=now() where id=v_uid returning * into v_row;
 if p_role='student' then insert into public.student_profiles(user_id) values(v_uid) on conflict do nothing;
 elsif p_role='parent' then insert into public.parent_profiles(user_id) values(v_uid) on conflict do nothing;
 elsif p_role='teacher' then insert into public.teacher_profiles(user_id) values(v_uid) on conflict do nothing;
 elsif p_role='company' then insert into public.company_profiles(user_id) values(v_uid) on conflict do nothing;
 end if;
 insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details) values(v_uid,'select_account_type','profile',v_uid,jsonb_build_object('role',p_role));
 return v_row;
end $$;
create or replace function public.select_account_type_v35(p_role public.user_role)
returns public.profiles language sql security invoker set search_path='' as $$ select * from private.select_account_type_v35(p_role); $$;
revoke all on function private.select_account_type_v35(public.user_role) from public,anon,authenticated;
revoke all on function public.select_account_type_v35(public.user_role) from public,anon;
grant execute on function public.select_account_type_v35(public.user_role) to authenticated;

create or replace function private.create_parent_link_invite_v35()
returns text language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_token text; v_hash text;
begin
 if v_uid is null then raise exception 'authentication required'; end if;
 if not exists(select 1 from public.profiles where id=v_uid and role='student'::public.user_role and account_status='active') then raise exception 'active student account required'; end if;
 v_token:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
 v_hash:=encode(sha256(v_token::bytea),'hex');
 delete from public.parent_link_invites where learner_id=v_uid and (redeemed_at is null or expires_at<now());
 insert into public.parent_link_invites(learner_id,token_hash,expires_at) values(v_uid,v_hash,now()+interval '30 minutes');
 return v_token;
end $$;
create or replace function public.create_parent_link_invite_v35()
returns text language sql security invoker set search_path='' as $$ select private.create_parent_link_invite_v35(); $$;
revoke all on function private.create_parent_link_invite_v35() from public,anon,authenticated;
revoke all on function public.create_parent_link_invite_v35() from public,anon;
grant execute on function public.create_parent_link_invite_v35() to authenticated;

create or replace function private.redeem_parent_link_invite_v35(p_token text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_inv public.parent_link_invites%rowtype; v_hash text; v_rel uuid;
begin
 if v_uid is null then raise exception 'authentication required'; end if;
 if not exists(select 1 from public.profiles where id=v_uid and role='parent'::public.user_role and account_status='active') then raise exception 'active parent account required'; end if;
 v_hash:=encode(sha256(trim(p_token)::bytea),'hex');
 select * into v_inv from public.parent_link_invites where token_hash=v_hash and redeemed_at is null and expires_at>now() for update;
 if not found then raise exception 'invalid or expired link code'; end if;
 if v_inv.learner_id=v_uid then raise exception 'cannot link account to itself'; end if;
 insert into public.guardian_relationships(learner_id,guardian_user_id,relationship,status,verified_at,verified_by)
 values(v_inv.learner_id,v_uid,'parent','verified',now(),v_uid)
 on conflict do nothing returning id into v_rel;
 if v_rel is null then select id into v_rel from public.guardian_relationships where learner_id=v_inv.learner_id and guardian_user_id=v_uid limit 1; end if;
 update public.parent_link_invites set redeemed_by=v_uid,redeemed_at=now() where id=v_inv.id;
 update public.profiles set learner_safety_status='guardian_verified',updated_at=now() where id=v_inv.learner_id and role='student'::public.user_role;
 insert into public.notifications(user_id,title,body,ref_table,ref_id) values(v_inv.learner_id,'Parent connected','A verified parent account was connected to your learning profile.','guardian_relationships',v_rel);
 insert into public.notifications(user_id,title,body,ref_table,ref_id) values(v_uid,'Child connected','Your parent account is now securely connected to the student profile.','guardian_relationships',v_rel);
 return v_rel;
end $$;
create or replace function public.redeem_parent_link_invite_v35(p_token text)
returns uuid language sql security invoker set search_path='' as $$ select private.redeem_parent_link_invite_v35(p_token); $$;
revoke all on function private.redeem_parent_link_invite_v35(text) from public,anon,authenticated;
revoke all on function public.redeem_parent_link_invite_v35(text) from public,anon;
grant execute on function public.redeem_parent_link_invite_v35(text) to authenticated;

alter table public.student_profiles enable row level security;
alter table public.parent_profiles enable row level security;
alter table public.teacher_profiles enable row level security;
alter table public.company_profiles enable row level security;
alter table public.subscription_plans enable row level security;
alter table public.user_subscriptions enable row level security;
alter table public.parent_link_invites enable row level security;

create policy student_profiles_self_select on public.student_profiles for select to authenticated using (user_id=(select auth.uid()) or private.has_verified_guardian_link((select auth.uid()),user_id) or private.is_admin_user());
create policy student_profiles_self_update on public.student_profiles for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy parent_profiles_self_select on public.parent_profiles for select to authenticated using (user_id=(select auth.uid()) or private.is_admin_user());
create policy parent_profiles_self_update on public.parent_profiles for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy teacher_profiles_self_select on public.teacher_profiles for select to authenticated using (user_id=(select auth.uid()) or private.is_admin_user());
create policy teacher_profiles_self_update on public.teacher_profiles for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy company_profiles_self_select on public.company_profiles for select to authenticated using (user_id=(select auth.uid()) or private.is_admin_user());
create policy company_profiles_self_update on public.company_profiles for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy subscription_plans_authenticated_read on public.subscription_plans for select to authenticated using (active=true);
create policy user_subscriptions_self_read on public.user_subscriptions for select to authenticated using (user_id=(select auth.uid()) or private.is_admin_user());
create policy parent_link_invites_owner_read on public.parent_link_invites for select to authenticated using (learner_id=(select auth.uid()) or redeemed_by=(select auth.uid()) or private.is_admin_user());

create policy parent_read_lesson_progress_v35 on public.lesson_progress for select to authenticated using (private.has_verified_guardian_link((select auth.uid()),user_id));
create policy parent_read_student_lesson_progress_v35 on public.student_lesson_progress for select to authenticated using (private.has_verified_guardian_link((select auth.uid()),user_id));
create policy parent_read_student_module_progress_v35 on public.student_module_progress for select to authenticated using (private.has_verified_guardian_link((select auth.uid()),user_id));

grant select,update on public.student_profiles,public.parent_profiles,public.teacher_profiles,public.company_profiles to authenticated;
grant select on public.subscription_plans,public.user_subscriptions,public.parent_link_invites to authenticated;

create or replace function private.protect_profile_security_fields()
returns trigger language plpgsql set search_path='pg_catalog','public','private' as $$
declare v_uid uuid := (select auth.uid()); v_is_admin boolean := false; v_server boolean := current_user in ('postgres','service_role');
begin
 if v_server then new.updated_at:=now(); return new; end if;
 if v_uid is not null then
   select exists(select 1 from public.profiles p where p.id=v_uid and p.role='admin'::public.user_role) into v_is_admin;
   if new.role is distinct from old.role and (v_uid=old.id or not v_is_admin) then raise exception 'role can only be changed by an administrator'; end if;
   if new.coin_balance is distinct from old.coin_balance and (v_uid=old.id or not v_is_admin) then raise exception 'coin balance can only be changed by an administrator or trusted backend'; end if;
   if new.verified_passport_badge_count is distinct from old.verified_passport_badge_count and (v_uid=old.id or not v_is_admin) then raise exception 'verified passport badge count is system managed'; end if;
   if (new.email_verified is distinct from old.email_verified or new.phone_verified is distinct from old.phone_verified) and (v_uid=old.id or not v_is_admin) then raise exception 'verification state is system managed'; end if;
   if (new.account_status is distinct from old.account_status or new.role_selected_at is distinct from old.role_selected_at or new.deleted_at is distinct from old.deleted_at) and (v_uid=old.id or not v_is_admin) then raise exception 'account security state is system managed'; end if;
 end if;
 new.updated_at:=now(); return new;
end $$;

create or replace function private.sync_auth_user_profile()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_provider text; v_verified boolean;
begin
 v_provider := coalesce(nullif(new.raw_app_meta_data ->> 'provider',''), case when new.phone is not null then 'phone' when new.email is not null then 'email' else 'unknown' end);
 v_verified := ((nullif(new.email,'') is not null and new.email_confirmed_at is not null) or (nullif(new.phone,'') is not null and new.phone_confirmed_at is not null));
 update public.profiles
 set email=nullif(new.email,''),phone_number=nullif(new.phone,''),
     full_name=coalesce(nullif(new.raw_user_meta_data ->> 'full_name',''),nullif(new.raw_user_meta_data ->> 'name',''),public.profiles.full_name),
     avatar_url=coalesce(public.profiles.avatar_url,nullif(new.raw_user_meta_data ->> 'avatar_url',''),nullif(new.raw_user_meta_data ->> 'picture','')),
     auth_provider=v_provider,
     email_verified=(nullif(new.email,'') is not null and new.email_confirmed_at is not null),
     phone_verified=(nullif(new.phone,'') is not null and new.phone_confirmed_at is not null),
     account_status=case when account_status='pending_verification' and v_verified then 'active' else account_status end,
     onboarding_step=case when onboarding_step='verify' and v_verified then 'role' else onboarding_step end,
     updated_at=now()
 where id=new.id;
 return new;
end $$;
;

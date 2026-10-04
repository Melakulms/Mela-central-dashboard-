-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813092206
alter table public.earnings_ledger drop constraint if exists earnings_ledger_source_type_check;
alter table public.earnings_ledger add constraint earnings_ledger_source_type_check check (source_type = any (array[
  'freelance_milestone'::text,'challenge_reward'::text,'arena_reward'::text,'tutoring'::text,'mentoring'::text,
  'referral_reward'::text,'onboarding_reward'::text,'creator_income'::text,'microtask'::text,'digital_product'::text,
  'course_sale'::text,'adjustment'::text
]));

create or replace function private.ledger_from_arena_reward()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  r record;
  v_count integer;
  v_each numeric;
  v_status text;
  v_when timestamptz;
begin
  if new.reward_type <> 'cash' or coalesce(new.cash_amount,0) <= 0 then return new; end if;
  if new.status not in ('available','paid') then return new; end if;
  if tg_op='UPDATE' and old.status is not distinct from new.status then return new; end if;
  v_status := case when new.status='paid' then 'paid' else 'available' end;
  v_when := coalesce(case when new.status='paid' then new.paid_at else new.available_at end, now());

  if new.beneficiary_user_id is not null then
    insert into public.earnings_ledger(user_id,source_type,source_id,gross_amount,platform_fee,net_amount,currency,status,external_ref,occurred_at)
    values(new.beneficiary_user_id,'arena_reward',new.id,new.cash_amount,0,new.cash_amount,coalesce(new.currency,'ETB'),v_status,new.external_ref,v_when)
    on conflict(source_type,source_id,user_id) do update set
      gross_amount=excluded.gross_amount, platform_fee=excluded.platform_fee, net_amount=excluded.net_amount,
      currency=excluded.currency, status=excluded.status, external_ref=excluded.external_ref, occurred_at=excluded.occurred_at;
    perform private.refresh_work_reputation(new.beneficiary_user_id,null);
  elsif new.beneficiary_arena_team_id is not null then
    select count(*) into v_count from public.arena_team_members where team_id=new.beneficiary_arena_team_id;
    if v_count>0 then
      v_each:=new.cash_amount/v_count;
      for r in select user_id from public.arena_team_members where team_id=new.beneficiary_arena_team_id loop
        insert into public.earnings_ledger(user_id,source_type,source_id,gross_amount,platform_fee,net_amount,currency,status,external_ref,occurred_at)
        values(r.user_id,'arena_reward',new.id,v_each,0,v_each,coalesce(new.currency,'ETB'),v_status,new.external_ref,v_when)
        on conflict(source_type,source_id,user_id) do update set status=excluded.status,external_ref=excluded.external_ref,occurred_at=excluded.occurred_at;
        perform private.refresh_work_reputation(r.user_id,null);
      end loop;
    end if;
  elsif new.beneficiary_tournament_team_id is not null then
    select count(*) into v_count from public.arena_tournament_team_members where team_id=new.beneficiary_tournament_team_id;
    if v_count>0 then
      v_each:=new.cash_amount/v_count;
      for r in select user_id from public.arena_tournament_team_members where team_id=new.beneficiary_tournament_team_id loop
        insert into public.earnings_ledger(user_id,source_type,source_id,gross_amount,platform_fee,net_amount,currency,status,external_ref,occurred_at)
        values(r.user_id,'arena_reward',new.id,v_each,0,v_each,coalesce(new.currency,'ETB'),v_status,new.external_ref,v_when)
        on conflict(source_type,source_id,user_id) do update set status=excluded.status,external_ref=excluded.external_ref,occurred_at=excluded.occurred_at;
        perform private.refresh_work_reputation(r.user_id,null);
      end loop;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_ledger_from_arena_reward on public.arena_rewards;
create trigger trg_ledger_from_arena_reward after insert or update of status,cash_amount,external_ref,paid_at,available_at on public.arena_rewards
for each row execute function private.ledger_from_arena_reward();

create or replace function public.get_my_wallet()
returns jsonb
language sql
stable
security invoker
set search_path=''
as $$
with me as (select (select auth.uid()) as uid),
ledger as (
  select l.* from public.earnings_ledger l, me where l.user_id=me.uid
),
source_breakdown as (
  select source_type,
    coalesce(sum(net_amount) filter (where status='available'),0) available,
    coalesce(sum(net_amount) filter (where status='pending'),0) pending,
    coalesce(sum(net_amount) filter (where status='paid'),0) paid,
    coalesce(sum(net_amount) filter (where status in ('available','paid')),0) lifetime
  from ledger group by source_type
),
payouts as (
  select r.* from public.payout_requests r, me where r.freelancer_id=me.uid order by r.created_at desc limit 10
),
account as (
  select a.user_id,a.account_name,a.bank_name,a.bank_code,a.currency,a.active,
         case when a.account_number is null then null else repeat('•',greatest(length(a.account_number)-4,0))||right(a.account_number,4) end masked_account
  from public.payout_accounts a, me where a.user_id=me.uid and a.active=true limit 1
)
select jsonb_build_object(
  'currency','ETB',
  'available_balance',coalesce((select sum(net_amount) from ledger where status='available' and upper(currency)='ETB'),0),
  'pending_earnings',coalesce((select sum(net_amount) from ledger where status='pending' and upper(currency)='ETB'),0),
  'paid_out',coalesce((select sum(net_amount) from ledger where status='paid' and upper(currency)='ETB'),0),
  'lifetime_earned',coalesce((select sum(net_amount) from ledger where status in ('available','paid') and upper(currency)='ETB'),0),
  'pending_payout',coalesce((select sum(amount_minor)::numeric/100 from payouts where status in ('pending','queued') and upper(currency)='ETB'),0),
  'source_breakdown',coalesce((select jsonb_agg(jsonb_build_object('source_type',source_type,'available',available,'pending',pending,'paid',paid,'lifetime',lifetime) order by lifetime desc) from source_breakdown),'[]'::jsonb),
  'recent_ledger',coalesce((select jsonb_agg(to_jsonb(x) order by x.occurred_at desc) from (select id,source_type,source_id,gross_amount,platform_fee,net_amount,currency,status,external_ref,occurred_at from ledger order by occurred_at desc limit 25) x),'[]'::jsonb),
  'payout_requests',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,milestone_id,amount_minor,currency,provider,payout_ref,status,failure_reason,created_at,completed_at from payouts order by created_at desc) x),'[]'::jsonb),
  'payout_account',coalesce((select to_jsonb(account) from account),'{}'::jsonb),
  'reputation',coalesce((select to_jsonb(w) from public.work_reputation w, me where w.user_id=me.uid),'{}'::jsonb),
  'arena_cash_pending',coalesce((select sum(r.cash_amount) from public.arena_rewards r, me where r.beneficiary_user_id=me.uid and r.reward_type='cash' and r.status='pending' and upper(coalesce(r.currency,'ETB'))='ETB'),0),
  'arena_cash_available',coalesce((select sum(r.cash_amount) from public.arena_rewards r, me where r.beneficiary_user_id=me.uid and r.reward_type='cash' and r.status='available' and upper(coalesce(r.currency,'ETB'))='ETB'),0),
  'payouts_enabled',coalesce((select enabled from public.platform_feature_flags where feature_key='payouts'),false)
);
$$;

revoke all on function public.get_my_wallet() from public, anon;
grant execute on function public.get_my_wallet() to authenticated, service_role;

create or replace function public.get_my_dashboard()
returns jsonb
language sql
stable
security invoker
set search_path=''
as $$
with me as (select (select auth.uid()) as uid),
profile as (
  select p.* from public.profiles p, me where p.id=me.uid
),
current_enrollment as (
  select e.id,e.career_path_id,e.status,e.progress_percent,e.lessons_completed,e.total_lessons,e.last_activity_at,
         cp.title career_path_title,cp.category career_path_category,cp.badge_title
  from public.career_path_enrollments e
  join public.career_paths cp on cp.id=e.career_path_id, me
  where e.user_id=me.uid and e.status in ('enrolled','in_progress','completed')
  order by case e.status when 'in_progress' then 0 when 'enrolled' then 1 else 2 end,e.last_activity_at desc nulls last limit 1
),
recent_apps as (
  select a.id,a.opportunity_id,a.status,a.applied_at,o.title,o.organization_name,o.opportunity_type
  from public.applications a join public.opportunities o on o.id=a.opportunity_id, me
  where coalesce(a.applicant_id,a.user_id)=me.uid order by a.applied_at desc limit 6
),
matched_opps as (
  select cm.id match_id,cm.match_score,cm.matched_skills,cm.missing_skills,cm.reasons,cm.status match_status,
         o.id opportunity_id,o.title,o.organization_name,o.opportunity_type,o.location,o.work_arrangement,o.deadline,o.stipend_or_reward
  from public.candidate_matches cm join public.opportunities o on o.id=cm.opportunity_id, me
  where cm.candidate_id=me.uid and o.status='open' and o.verified_active=true and (o.deadline is null or o.deadline>=current_date)
  order by cm.match_score desc nulls last,cm.generated_at desc limit 8
),
coach_items as (
  select i.id,i.title,i.item_type,i.priority,i.status,i.due_at,i.related_table,i.related_id,i.notes
  from public.career_coach_action_items i
  join public.career_coach_action_plans p on p.id=i.plan_id, me
  where p.user_id=me.uid and p.status='active' and i.status='todo'
  order by i.priority asc,i.due_at asc nulls last,i.created_at asc limit 5
),
weak_practice as (
  select pm.topic_id,pm.mastery_level,pm.mastery_score,pm.accuracy_percent,pt.subject,pt.topic
  from public.practice_mastery pm join public.practice_topics pt on pt.id=pm.topic_id, me
  where pm.user_id=me.uid and pm.mastery_level in ('weak','developing')
  order by pm.mastery_score asc nulls first,pm.last_practiced_at desc nulls last limit 4
),
recent_notifications as (
  select n.id,n.title,n.body,n.ref_table,n.ref_id,n.is_read,n.created_at from public.notifications n, me where n.user_id=me.uid order by n.created_at desc limit 8
),
recent_achievements as (
  select a.id,a.achievement_type,a.title,a.issuer,a.description,a.placement,a.score,a.verified,a.evidence_url,a.created_at
  from public.career_passport_achievements a, me where a.user_id=me.uid and a.is_public=true order by a.created_at desc limit 6
),
scholarships as (
  select o.id,o.title,o.organization_name,o.location,o.deadline,o.stipend_or_reward,s.institution,s.program_name,s.study_country,s.funding_type,s.coverage
  from public.opportunities o join public.scholarship_details s on s.opportunity_id=o.id
  where o.opportunity_type='scholarships'::public.opportunity_type and o.status='open' and o.verified_active=true and (o.deadline is null or o.deadline>=current_date)
  order by o.deadline asc nulls last limit 5
)
select jsonb_build_object(
  'profile',coalesce((select jsonb_build_object('id',id,'full_name',full_name,'email',email,'role',role,'avatar_url',avatar_url,'university',university,'major',major,'city',city,'preferred_language',preferred_language,'availability_status',availability_status,'verified_passport_badge_count',verified_passport_badge_count) from profile),'{}'::jsonb),
  'feature_flags',coalesce((select jsonb_object_agg(feature_key,enabled) from public.platform_feature_flags),'{}'::jsonb),
  'passport',coalesce(public.get_my_career_passport_summary(),'{}'::jsonb),
  'current_path',coalesce((select to_jsonb(current_enrollment) from current_enrollment),'{}'::jsonb),
  'verified_skills',coalesce((select jsonb_agg(to_jsonb(x) order by x.issued_at desc) from (select id,skill_name,category,level,score,verification_source,issued_at from public.verified_skills v,me where v.user_id=me.uid and v.verified=true order by issued_at desc limit 8) x),'[]'::jsonb),
  'applications',jsonb_build_object(
    'total',(select count(*) from public.applications a,me where coalesce(a.applicant_id,a.user_id)=me.uid),
    'active',(select count(*) from public.applications a,me where coalesce(a.applicant_id,a.user_id)=me.uid and a.status in ('submitted','reviewing','shortlisted','interview','offered')),
    'hired',(select count(*) from public.applications a,me where coalesce(a.applicant_id,a.user_id)=me.uid and a.status='hired'),
    'recent',coalesce((select jsonb_agg(to_jsonb(recent_apps) order by recent_apps.applied_at desc) from recent_apps),'[]'::jsonb)
  ),
  'opportunity_matches',coalesce((select jsonb_agg(to_jsonb(matched_opps) order by matched_opps.match_score desc nulls last) from matched_opps),'[]'::jsonb),
  'saved_opportunities',(select count(*) from public.saved_opportunities s,me where s.user_id=me.uid),
  'coach_actions',coalesce((select jsonb_agg(to_jsonb(coach_items) order by coach_items.priority,coach_items.due_at nulls last) from coach_items),'[]'::jsonb),
  'weak_practice',coalesce((select jsonb_agg(to_jsonb(weak_practice) order by weak_practice.mastery_score asc nulls first) from weak_practice),'[]'::jsonb),
  'practice',coalesce(public.get_my_practice_dashboard(),'{}'::jsonb),
  'arena',coalesce(public.get_my_arena_stats(),'{}'::jsonb),
  'wallet',coalesce(public.get_my_wallet(),'{}'::jsonb),
  'notifications',coalesce((select jsonb_agg(to_jsonb(recent_notifications) order by recent_notifications.created_at desc) from recent_notifications),'[]'::jsonb),
  'unread_notifications',(select count(*) from public.notifications n,me where n.user_id=me.uid and n.is_read=false),
  'achievements',coalesce((select jsonb_agg(to_jsonb(recent_achievements) order by recent_achievements.created_at desc) from recent_achievements),'[]'::jsonb),
  'scholarships',coalesce((select jsonb_agg(to_jsonb(scholarships) order by scholarships.deadline asc nulls last) from scholarships),'[]'::jsonb)
);
$$;

revoke all on function public.get_my_dashboard() from public, anon;
grant execute on function public.get_my_dashboard() to authenticated, service_role;

create or replace function public.get_my_employer_dashboard()
returns jsonb
language sql
stable
security invoker
set search_path=''
as $$
with me as (select (select auth.uid()) uid),
company as (
  select e.* from public.employers e,me where e.owner_id=me.uid
  union all
  select e.* from public.employer_members m join public.employers e on e.id=m.employer_id,me where m.user_id=me.uid and m.status='active'
  limit 1
),
opp as (
  select o.* from public.opportunities o join company c on c.id=o.employer_id
),
apps as (
  select a.id,a.opportunity_id,a.status,a.applied_at,a.applicant_id,a.user_id,p.full_name,p.university,p.major,o.title opportunity_title
  from public.applications a join opp o on o.id=a.opportunity_id left join public.profiles p on p.id=coalesce(a.applicant_id,a.user_id)
  order by a.applied_at desc
),
matches as (
  select cm.id,cm.opportunity_id,cm.candidate_id,cm.match_score,cm.matched_skills,cm.missing_skills,cm.status,p.full_name,p.university,p.major,o.title opportunity_title
  from public.candidate_matches cm join opp o on o.id=cm.opportunity_id left join public.profiles p on p.id=cm.candidate_id
  order by cm.match_score desc nulls last,cm.generated_at desc
),
tasks as (
  select t.* from public.marketplace_tasks t join company c on c.id=t.employer_id
),
contracts as (
  select fc.* from public.freelance_contracts fc join company c on c.id=fc.employer_id
)
select jsonb_build_object(
  'company',coalesce((select to_jsonb(company) from company),'{}'::jsonb),
  'feature_flags',coalesce((select jsonb_object_agg(feature_key,enabled) from public.platform_feature_flags),'{}'::jsonb),
  'opportunities',jsonb_build_object(
    'total',(select count(*) from opp),
    'open',(select count(*) from opp where status='open'),
    'draft',(select count(*) from opp where status='draft'),
    'recent',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,title,status,opportunity_type,location,deadline,openings_count,created_at from opp order by created_at desc limit 10) x),'[]'::jsonb)
  ),
  'applications',jsonb_build_object(
    'total',(select count(*) from apps),
    'new',(select count(*) from apps where status='submitted'),
    'shortlisted',(select count(*) from apps where status='shortlisted'),
    'interview',(select count(*) from apps where status='interview'),
    'hired',(select count(*) from apps where status='hired'),
    'recent',coalesce((select jsonb_agg(to_jsonb(x) order by x.applied_at desc) from (select * from apps limit 12) x),'[]'::jsonb)
  ),
  'talent_matches',coalesce((select jsonb_agg(to_jsonb(x) order by x.match_score desc nulls last) from (select * from matches limit 12) x),'[]'::jsonb),
  'work',jsonb_build_object(
    'tasks_total',(select count(*) from tasks),
    'tasks_open',(select count(*) from tasks where status='open'),
    'contracts_active',(select count(*) from contracts where status='active'),
    'contracts_completed',(select count(*) from contracts where status='completed'),
    'recent_tasks',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,title,status,budget_amount,currency,deadline,created_at from tasks order by created_at desc limit 8) x),'[]'::jsonb)
  ),
  'challenges',jsonb_build_object(
    'total',(select count(*) from public.sponsored_challenges sc join company c on c.id=sc.sponsor_employer_id),
    'active',(select count(*) from public.sponsored_challenges sc join company c on c.id=sc.sponsor_employer_id where sc.status in ('published','open','judging'))
  )
);
$$;

revoke all on function public.get_my_employer_dashboard() from public, anon;
grant execute on function public.get_my_employer_dashboard() to authenticated, service_role;

;

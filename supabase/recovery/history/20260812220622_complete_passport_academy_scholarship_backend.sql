-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812220622
-- Career Passport summary, Skill Academy enrollments/certificates, Opportunity saves/reminders, Scholarship Connect

create table if not exists public.career_path_enrollments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  career_path_id uuid not null references public.career_paths(id) on delete cascade,
  status text not null default 'enrolled' check (status in ('enrolled','in_progress','paused','completed')),
  progress_percent integer not null default 0 check (progress_percent between 0 and 100),
  lessons_completed integer not null default 0 check (lessons_completed >= 0),
  total_lessons integer not null default 0 check (total_lessons >= 0),
  proctored_required integer not null default 0 check (proctored_required >= 0),
  proctored_passed integer not null default 0 check (proctored_passed >= 0),
  enrolled_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  last_activity_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id,career_path_id)
);

create table if not exists public.skill_academy_certificates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  career_path_id uuid not null references public.career_paths(id) on delete cascade,
  certificate_code text not null unique,
  final_progress integer not null default 100 check (final_progress between 0 and 100),
  metadata jsonb not null default '{}'::jsonb,
  issued_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoke_reason text,
  unique(user_id,career_path_id)
);

create table if not exists public.saved_opportunities (
  user_id uuid not null references public.profiles(id) on delete cascade,
  opportunity_id uuid not null references public.opportunities(id) on delete cascade,
  note text,
  saved_at timestamptz not null default now(),
  primary key(user_id,opportunity_id)
);

create table if not exists public.opportunity_reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  opportunity_id uuid not null references public.opportunities(id) on delete cascade,
  remind_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending','sent','cancelled')),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  unique(user_id,opportunity_id,remind_at)
);

create table if not exists public.scholarship_details (
  opportunity_id uuid primary key references public.opportunities(id) on delete cascade,
  institution text not null,
  program_name text,
  study_country text not null,
  degree_levels text[] not null default '{}',
  fields_of_study text[] not null default '{}',
  eligible_countries text[] not null default '{}',
  minimum_gpa numeric(4,2),
  funding_type text not null default 'unspecified' check (funding_type in ('full','partial','tuition_only','stipend','research','unspecified')),
  coverage text[] not null default '{}',
  award_amount numeric,
  award_currency text,
  language_requirements text[] not null default '{}',
  required_documents text[] not null default '{}',
  intake_label text,
  application_fee numeric,
  application_fee_currency text,
  eligibility_rules jsonb not null default '{}'::jsonb,
  source_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scholarship_min_gpa_chk check (minimum_gpa is null or (minimum_gpa >= 0 and minimum_gpa <= 4.00)),
  constraint scholarship_award_chk check (award_amount is null or award_amount >= 0),
  constraint scholarship_fee_chk check (application_fee is null or application_fee >= 0)
);

create index if not exists career_path_enrollments_user_status_idx on public.career_path_enrollments(user_id,status);
create index if not exists career_path_enrollments_path_idx on public.career_path_enrollments(career_path_id);
create index if not exists academy_certificates_user_idx on public.skill_academy_certificates(user_id,issued_at desc);
create index if not exists saved_opportunities_opportunity_idx on public.saved_opportunities(opportunity_id);
create index if not exists opportunity_reminders_due_idx on public.opportunity_reminders(status,remind_at) where status='pending';
create index if not exists scholarship_details_country_idx on public.scholarship_details(study_country);
create index if not exists scholarship_details_fields_gin_idx on public.scholarship_details using gin(fields_of_study);

alter table public.career_path_enrollments enable row level security;
alter table public.skill_academy_certificates enable row level security;
alter table public.saved_opportunities enable row level security;
alter table public.opportunity_reminders enable row level security;
alter table public.scholarship_details enable row level security;

-- Explicit grants for 2026 Data API behavior.
revoke all on public.career_path_enrollments, public.skill_academy_certificates, public.saved_opportunities, public.opportunity_reminders, public.scholarship_details from anon, authenticated;
grant select on public.career_path_enrollments, public.skill_academy_certificates, public.saved_opportunities, public.opportunity_reminders, public.scholarship_details to authenticated;
grant insert on public.career_path_enrollments, public.saved_opportunities, public.opportunity_reminders to authenticated;
grant update(status) on public.career_path_enrollments to authenticated;
grant update(note) on public.saved_opportunities to authenticated;
grant update(remind_at,status) on public.opportunity_reminders to authenticated;
grant delete on public.saved_opportunities, public.opportunity_reminders to authenticated;
grant select on public.scholarship_details to anon;
grant insert,update,delete on public.scholarship_details to authenticated;
grant all on public.career_path_enrollments, public.skill_academy_certificates, public.saved_opportunities, public.opportunity_reminders, public.scholarship_details to service_role;

-- RLS: academy enrollments and certificates.
drop policy if exists "Academy enrollments owner read" on public.career_path_enrollments;
create policy "Academy enrollments owner read" on public.career_path_enrollments for select to authenticated
using (user_id=(select auth.uid()) or private.is_admin_user());

drop policy if exists "Students enroll in career paths" on public.career_path_enrollments;
create policy "Students enroll in career paths" on public.career_path_enrollments for insert to authenticated
with check (
  user_id=(select auth.uid()) and status='enrolled' and progress_percent=0 and lessons_completed=0
  and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='student'::public.user_role)
);

drop policy if exists "Students pause or resume academy enrollment" on public.career_path_enrollments;
create policy "Students pause or resume academy enrollment" on public.career_path_enrollments for update to authenticated
using (user_id=(select auth.uid()) and status in ('enrolled','in_progress','paused'))
with check (user_id=(select auth.uid()) and status in ('enrolled','in_progress','paused'));

drop policy if exists "Academy certificates readable" on public.skill_academy_certificates;
create policy "Academy certificates readable" on public.skill_academy_certificates for select to authenticated
using (user_id=(select auth.uid()) or private.is_admin_user());

-- Saved opportunities/reminders.
drop policy if exists "Saved opportunities owner read" on public.saved_opportunities;
create policy "Saved opportunities owner read" on public.saved_opportunities for select to authenticated using (user_id=(select auth.uid()));
drop policy if exists "Saved opportunities owner insert" on public.saved_opportunities;
create policy "Saved opportunities owner insert" on public.saved_opportunities for insert to authenticated
with check (user_id=(select auth.uid()) and exists(select 1 from public.opportunities o where o.id=opportunity_id));
drop policy if exists "Saved opportunities owner update" on public.saved_opportunities;
create policy "Saved opportunities owner update" on public.saved_opportunities for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
drop policy if exists "Saved opportunities owner delete" on public.saved_opportunities;
create policy "Saved opportunities owner delete" on public.saved_opportunities for delete to authenticated using (user_id=(select auth.uid()));

drop policy if exists "Opportunity reminders owner read" on public.opportunity_reminders;
create policy "Opportunity reminders owner read" on public.opportunity_reminders for select to authenticated using (user_id=(select auth.uid()));
drop policy if exists "Opportunity reminders owner insert" on public.opportunity_reminders;
create policy "Opportunity reminders owner insert" on public.opportunity_reminders for insert to authenticated
with check (user_id=(select auth.uid()) and status='pending' and remind_at>now());
drop policy if exists "Opportunity reminders owner update" on public.opportunity_reminders;
create policy "Opportunity reminders owner update" on public.opportunity_reminders for update to authenticated
using (user_id=(select auth.uid()) and status='pending')
with check (user_id=(select auth.uid()) and status in ('pending','cancelled'));
drop policy if exists "Opportunity reminders owner delete" on public.opportunity_reminders;
create policy "Opportunity reminders owner delete" on public.opportunity_reminders for delete to authenticated using (user_id=(select auth.uid()));

-- Scholarship details are public only when the underlying opportunity is live; owners/admin can inspect drafts.
drop policy if exists "Scholarship details readable" on public.scholarship_details;
create policy "Scholarship details readable" on public.scholarship_details for select to anon, authenticated
using (
  exists(select 1 from public.opportunities o where o.id=opportunity_id and o.opportunity_type='scholarships'::public.opportunity_type and o.status='open' and o.verified_active=true and o.deadline>=current_date)
  or (case when (select auth.uid()) is not null then exists(select 1 from public.opportunities o where o.id=opportunity_id and (private.has_employer_access(o.employer_id,false) or private.is_admin_user())) else false end)
);

drop policy if exists "Employer teams create scholarship details" on public.scholarship_details;
create policy "Employer teams create scholarship details" on public.scholarship_details for insert to authenticated
with check (exists(select 1 from public.opportunities o where o.id=opportunity_id and o.opportunity_type='scholarships'::public.opportunity_type and (private.has_employer_access(o.employer_id,true) or private.is_admin_user())));
drop policy if exists "Employer teams update scholarship details" on public.scholarship_details;
create policy "Employer teams update scholarship details" on public.scholarship_details for update to authenticated
using (exists(select 1 from public.opportunities o where o.id=opportunity_id and (private.has_employer_access(o.employer_id,true) or private.is_admin_user())))
with check (exists(select 1 from public.opportunities o where o.id=opportunity_id and o.opportunity_type='scholarships'::public.opportunity_type and (private.has_employer_access(o.employer_id,true) or private.is_admin_user())));
drop policy if exists "Employer teams delete scholarship details" on public.scholarship_details;
create policy "Employer teams delete scholarship details" on public.scholarship_details for delete to authenticated
using (exists(select 1 from public.opportunities o where o.id=opportunity_id and (private.has_employer_access(o.employer_id,true) or private.is_admin_user())));

-- Client updates cannot forge server-calculated academy completion fields.
create or replace function private.protect_career_path_enrollment()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if (select auth.uid()) is not null and not private.is_admin_user() then
    if tg_op='UPDATE' then
      if new.progress_percent is distinct from old.progress_percent
        or new.lessons_completed is distinct from old.lessons_completed
        or new.total_lessons is distinct from old.total_lessons
        or new.proctored_required is distinct from old.proctored_required
        or new.proctored_passed is distinct from old.proctored_passed
        or new.completed_at is distinct from old.completed_at
        or new.user_id is distinct from old.user_id
        or new.career_path_id is distinct from old.career_path_id then
        raise exception 'academy completion fields are server managed';
      end if;
      if new.status='completed' and old.status<>'completed' then
        raise exception 'academy completion status is server managed';
      end if;
    end if;
  end if;
  new.updated_at:=now();
  return new;
end; $$;
drop trigger if exists trg_protect_career_path_enrollment on public.career_path_enrollments;
create trigger trg_protect_career_path_enrollment before update on public.career_path_enrollments
for each row execute function private.protect_career_path_enrollment();

create or replace function private.refresh_career_path_enrollment(p_user_id uuid,p_path_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare
  v_total int:=0; v_done int:=0; v_req int:=0; v_pass int:=0; v_pct int:=0; v_cert uuid;
begin
  select count(*) into v_total from public.path_lessons l join public.path_modules m on m.id=l.module_id where m.career_path_id=p_path_id and l.is_published=true;
  select count(*) into v_done from public.student_lesson_progress sp join public.path_lessons l on l.id=sp.lesson_id join public.path_modules m on m.id=l.module_id
    where sp.user_id=p_user_id and m.career_path_id=p_path_id and l.is_published=true and (sp.status='completed' or sp.progress_percent=100);
  select count(*) into v_req from public.path_modules m where m.career_path_id=p_path_id and m.is_proctored_assessment=true;
  select count(*) into v_pass from public.student_module_progress sm join public.path_modules m on m.id=sm.module_id
    where sm.user_id=p_user_id and m.career_path_id=p_path_id and m.is_proctored_assessment=true and sm.proctored_passed=true;
  v_pct:=case when v_total=0 then 0 else least(100,round(v_done*100.0/v_total)::int) end;

  insert into public.career_path_enrollments(user_id,career_path_id,status,progress_percent,lessons_completed,total_lessons,proctored_required,proctored_passed,started_at,last_activity_at)
  values(p_user_id,p_path_id,case when v_done>0 then 'in_progress' else 'enrolled' end,v_pct,v_done,v_total,v_req,v_pass,case when v_done>0 then now() end,now())
  on conflict(user_id,career_path_id) do update set
    progress_percent=excluded.progress_percent,lessons_completed=excluded.lessons_completed,total_lessons=excluded.total_lessons,
    proctored_required=excluded.proctored_required,proctored_passed=excluded.proctored_passed,
    status=case when excluded.progress_percent=100 and excluded.proctored_passed>=excluded.proctored_required then 'completed'
                when public.career_path_enrollments.status='paused' then 'paused'
                when excluded.lessons_completed>0 then 'in_progress' else 'enrolled' end,
    started_at=coalesce(public.career_path_enrollments.started_at,case when excluded.lessons_completed>0 then now() end),
    completed_at=case when excluded.progress_percent=100 and excluded.proctored_passed>=excluded.proctored_required then coalesce(public.career_path_enrollments.completed_at,now()) else null end,
    last_activity_at=now(),updated_at=now();

  if v_pct=100 and v_pass>=v_req then
    insert into public.skill_academy_certificates(user_id,career_path_id,certificate_code,final_progress,metadata)
    values(p_user_id,p_path_id,'MELA-'||upper(substr(md5(gen_random_uuid()::text),1,12)),100,jsonb_build_object('proctored_required',v_req,'proctored_passed',v_pass))
    on conflict(user_id,career_path_id) do nothing
    returning id into v_cert;
    if v_cert is not null then
      perform private.create_notification(p_user_id,'Skill Academy certificate earned','You completed a Mela career path and earned a verified completion certificate.','skill_academy_certificates',v_cert);
    end if;
  end if;
end; $$;

create or replace function private.refresh_academy_from_lesson_progress()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_user uuid; v_path uuid;
begin
  v_user:=coalesce(new.user_id,old.user_id);
  select m.career_path_id into v_path from public.path_lessons l join public.path_modules m on m.id=l.module_id where l.id=coalesce(new.lesson_id,old.lesson_id);
  if v_path is not null then perform private.refresh_career_path_enrollment(v_user,v_path); end if;
  return coalesce(new,old);
end; $$;
drop trigger if exists trg_refresh_academy_from_lesson on public.student_lesson_progress;
create trigger trg_refresh_academy_from_lesson after insert or update or delete on public.student_lesson_progress
for each row execute function private.refresh_academy_from_lesson_progress();

create or replace function private.refresh_academy_from_module_progress()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_user uuid; v_path uuid;
begin
  v_user:=coalesce(new.user_id,old.user_id);
  select career_path_id into v_path from public.path_modules where id=coalesce(new.module_id,old.module_id);
  if v_path is not null then perform private.refresh_career_path_enrollment(v_user,v_path); end if;
  return coalesce(new,old);
end; $$;
drop trigger if exists trg_refresh_academy_from_module on public.student_module_progress;
create trigger trg_refresh_academy_from_module after insert or update or delete on public.student_module_progress
for each row execute function private.refresh_academy_from_module_progress();

-- Backfill enrollment rows from existing progress, without hard-coded IDs.
insert into public.career_path_enrollments(user_id,career_path_id)
select distinct sp.user_id,m.career_path_id
from public.student_lesson_progress sp join public.path_lessons l on l.id=sp.lesson_id join public.path_modules m on m.id=l.module_id
on conflict(user_id,career_path_id) do nothing;

do $$ declare r record; begin
  for r in select user_id,career_path_id from public.career_path_enrollments loop
    perform private.refresh_career_path_enrollment(r.user_id,r.career_path_id);
  end loop;
end $$;

-- Self-service enrollment RPC.
create or replace function public.enroll_career_path(p_career_path_id uuid)
returns public.career_path_enrollments
language plpgsql security invoker set search_path=''
as $$
declare v_row public.career_path_enrollments;
begin
  if (select auth.uid()) is null then raise exception 'authentication required'; end if;
  insert into public.career_path_enrollments(user_id,career_path_id)
  values((select auth.uid()),p_career_path_id)
  on conflict(user_id,career_path_id) do update set status=case when public.career_path_enrollments.status='paused' then 'in_progress' else public.career_path_enrollments.status end,last_activity_at=now()
  returning * into v_row;
  return v_row;
end; $$;
revoke all on function public.enroll_career_path(uuid) from public,anon;
grant execute on function public.enroll_career_path(uuid) to authenticated,service_role;

-- Career Passport completeness/summary for the signed-in user.
create or replace function public.get_my_career_passport_summary()
returns jsonb language sql stable security invoker set search_path=''
as $$
select jsonb_build_object(
  'user_id',p.id,
  'profile_score',(
    (case when nullif(p.full_name,'') is not null then 10 else 0 end)+
    (case when nullif(p.bio,'') is not null then 10 else 0 end)+
    (case when nullif(p.university,'') is not null or nullif(p.school_name,'') is not null then 10 else 0 end)+
    (case when nullif(p.major,'') is not null then 10 else 0 end)+
    (case when nullif(p.city,'') is not null or nullif(p.region,'') is not null then 10 else 0 end)+
    (case when exists(select 1 from public.profile_education e where e.user_id=p.id) then 10 else 0 end)+
    (case when exists(select 1 from public.profile_experience e where e.user_id=p.id) then 10 else 0 end)+
    (case when exists(select 1 from public.profile_projects pr where pr.user_id=p.id) then 10 else 0 end)+
    (case when exists(select 1 from public.profile_languages l where l.user_id=p.id) then 10 else 0 end)+
    (case when exists(select 1 from public.verified_skills s where s.user_id=p.id and s.verified=true) then 10 else 0 end)
  ),
  'education_count',(select count(*) from public.profile_education e where e.user_id=p.id),
  'experience_count',(select count(*) from public.profile_experience e where e.user_id=p.id),
  'project_count',(select count(*) from public.profile_projects pr where pr.user_id=p.id),
  'language_count',(select count(*) from public.profile_languages l where l.user_id=p.id),
  'verified_skill_count',(select count(*) from public.verified_skills s where s.user_id=p.id and s.verified=true),
  'document_count',(select count(*) from public.profile_documents d where d.user_id=p.id),
  'verified_document_count',(select count(*) from public.profile_documents d where d.user_id=p.id and d.verified=true),
  'badge_count',(select count(*) from public.user_badges b where b.user_id=p.id)
) from public.profiles p where p.id=(select auth.uid());
$$;
revoke all on function public.get_my_career_passport_summary() from public,anon;
grant execute on function public.get_my_career_passport_summary() to authenticated,service_role;

-- Scholarship eligibility matching based on the user's current Mela profile.
create or replace function public.check_scholarship_eligibility(p_opportunity_id uuid)
returns jsonb language plpgsql stable security invoker set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_p public.profiles; v_s public.scholarship_details; v_o public.opportunities; v_score int:=0; v_checks jsonb:='[]'::jsonb; v_field_ok boolean:=true; v_gpa_ok boolean:=true;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_p from public.profiles where id=v_uid;
  select * into v_o from public.opportunities where id=p_opportunity_id;
  if not found or v_o.opportunity_type<>'scholarships'::public.opportunity_type then raise exception 'scholarship opportunity not found'; end if;
  select * into v_s from public.scholarship_details where opportunity_id=p_opportunity_id;
  if not found then return jsonb_build_object('score',0,'eligible',false,'checks',jsonb_build_array(jsonb_build_object('check','details','passed',false,'reason','Scholarship eligibility details are not available yet'))); end if;

  if v_s.minimum_gpa is null then v_gpa_ok:=true; v_score:=v_score+40;
  elsif v_p.gpa is not null and v_p.gpa>=v_s.minimum_gpa then v_gpa_ok:=true; v_score:=v_score+40;
  else v_gpa_ok:=false; end if;
  v_checks:=v_checks||jsonb_build_array(jsonb_build_object('check','minimum_gpa','passed',v_gpa_ok,'required',v_s.minimum_gpa,'current',v_p.gpa));

  if coalesce(array_length(v_s.fields_of_study,1),0)=0 then v_field_ok:=true; v_score:=v_score+35;
  elsif v_p.major is not null and exists(select 1 from unnest(v_s.fields_of_study) f where lower(f)=lower(v_p.major) or lower(v_p.major) like '%'||lower(f)||'%' or lower(f) like '%'||lower(v_p.major)||'%') then v_field_ok:=true; v_score:=v_score+35;
  else v_field_ok:=false; end if;
  v_checks:=v_checks||jsonb_build_array(jsonb_build_object('check','field_of_study','passed',v_field_ok,'required',to_jsonb(v_s.fields_of_study),'current',v_p.major));

  if v_p.university is not null or v_p.school_name is not null then v_score:=v_score+15; end if;
  if exists(select 1 from public.profile_documents d where d.user_id=v_uid) then v_score:=v_score+10; end if;

  return jsonb_build_object('opportunity_id',p_opportunity_id,'score',least(v_score,100),'eligible',v_gpa_ok and v_field_ok,'checks',v_checks,'deadline',v_o.deadline,'institution',v_s.institution,'study_country',v_s.study_country,'funding_type',v_s.funding_type);
end; $$;
revoke all on function public.check_scholarship_eligibility(uuid) from public,anon;
grant execute on function public.check_scholarship_eligibility(uuid) to authenticated,service_role;

-- Due reminder processor, run by pg_cron.
create or replace function private.process_due_opportunity_reminders()
returns integer language plpgsql security definer set search_path=''
as $$
declare r record; v_count int:=0;
begin
  for r in select rem.id,rem.user_id,rem.opportunity_id,o.title,o.deadline from public.opportunity_reminders rem join public.opportunities o on o.id=rem.opportunity_id where rem.status='pending' and rem.remind_at<=now() for update skip locked loop
    perform private.create_notification(r.user_id,'Opportunity reminder',r.title||case when r.deadline is not null then ' — deadline '||r.deadline::text else '' end,'opportunities',r.opportunity_id);
    update public.opportunity_reminders set status='sent',sent_at=now() where id=r.id;
    v_count:=v_count+1;
  end loop;
  return v_count;
end; $$;

-- Replace this named cron job if it already exists.
do $$ declare v_job bigint; begin
  select jobid into v_job from cron.job where jobname='mela-opportunity-reminders' limit 1;
  if v_job is not null then perform cron.unschedule(v_job); end if;
  perform cron.schedule('mela-opportunity-reminders','*/15 * * * *','select private.process_due_opportunity_reminders();');
end $$;

;

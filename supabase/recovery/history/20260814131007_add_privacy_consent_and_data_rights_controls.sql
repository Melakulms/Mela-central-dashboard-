-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814131007
create table if not exists public.policy_documents (
  policy_key text not null,
  version text not null,
  title text not null,
  status text not null default 'draft' check (status in ('draft','active','retired')),
  required_for_access boolean not null default false,
  explicit_consent boolean not null default false,
  revocable boolean not null default false,
  scope text not null default 'platform',
  effective_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(policy_key,version)
);
alter table public.policy_documents enable row level security;
revoke all on public.policy_documents from public,anon,authenticated;
grant select on public.policy_documents to anon,authenticated,service_role;
grant insert,update,delete on public.policy_documents to service_role;
drop policy if exists policy_documents_public_active_read on public.policy_documents;
create policy policy_documents_public_active_read on public.policy_documents for select to anon,authenticated using (status='active');

insert into public.policy_documents(policy_key,version,title,status,required_for_access,explicit_consent,revocable,scope,effective_at)
values
 ('terms','2026-08-14','Mela Terms of Service','active',true,false,false,'platform',now()),
 ('privacy','2026-08-14','Mela Privacy Notice','active',true,false,false,'platform',now()),
 ('proctoring','2026-08-14','Mela Assessment & Proctoring Consent','active',false,true,true,'assessments',now()),
 ('ai_disclosure','2026-08-14','Mela AI Assistance Disclosure','active',false,false,true,'ai',now()),
 ('adult_work_eligibility','2026-08-14','18+ Work & Financial Eligibility Attestation','active',false,true,true,'earn_work',now())
on conflict (policy_key,version) do update set title=excluded.title,status=excluded.status,required_for_access=excluded.required_for_access,explicit_consent=excluded.explicit_consent,revocable=excluded.revocable,scope=excluded.scope,effective_at=excluded.effective_at,updated_at=now();

create table if not exists public.user_policy_acknowledgements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  policy_key text not null,
  policy_version text not null,
  accepted boolean not null default true,
  accepted_at timestamptz not null default now(),
  revoked_at timestamptz,
  language text not null default 'English' check (language in ('English','Amharic','Afaan Oromo','Tigrinya','Somali')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id,policy_key,policy_version),
  foreign key(policy_key,policy_version) references public.policy_documents(policy_key,version) on update cascade on delete restrict
);
create index if not exists user_policy_ack_user_key_idx on public.user_policy_acknowledgements(user_id,policy_key,accepted,revoked_at);
alter table public.user_policy_acknowledgements enable row level security;
revoke all on public.user_policy_acknowledgements from public,anon,authenticated;
grant select,insert,update on public.user_policy_acknowledgements to authenticated,service_role;
grant delete on public.user_policy_acknowledgements to service_role;
drop policy if exists user_policy_ack_owner_read on public.user_policy_acknowledgements;
create policy user_policy_ack_owner_read on public.user_policy_acknowledgements for select to authenticated using (user_id=(select auth.uid()) or private.is_admin_user());
drop policy if exists user_policy_ack_owner_insert on public.user_policy_acknowledgements;
create policy user_policy_ack_owner_insert on public.user_policy_acknowledgements for insert to authenticated with check (user_id=(select auth.uid()));
drop policy if exists user_policy_ack_owner_update on public.user_policy_acknowledgements;
create policy user_policy_ack_owner_update on public.user_policy_acknowledgements for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));

create or replace function public.record_my_policy_acknowledgement(p_policy_key text,p_accept boolean default true,p_metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security invoker
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_doc public.policy_documents%rowtype;
  v_lang text;
  v_row public.user_policy_acknowledgements%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_doc from public.policy_documents where policy_key=p_policy_key and status='active' order by effective_at desc nulls last,version desc limit 1;
  if not found then raise exception 'active policy not found'; end if;
  if not p_accept and not v_doc.revocable then raise exception 'this acknowledgement is not revocable; use account deletion/data-rights controls if you no longer wish to use Mela'; end if;
  select preferred_language into v_lang from public.profiles where id=v_uid;
  insert into public.user_policy_acknowledgements(user_id,policy_key,policy_version,accepted,accepted_at,revoked_at,language,metadata,updated_at)
  values(v_uid,v_doc.policy_key,v_doc.version,p_accept,now(),case when p_accept then null else now() end,coalesce(v_lang,'English'),coalesce(p_metadata,'{}'::jsonb),now())
  on conflict(user_id,policy_key,policy_version) do update set accepted=excluded.accepted,accepted_at=case when excluded.accepted then now() else public.user_policy_acknowledgements.accepted_at end,revoked_at=case when excluded.accepted then null else now() end,language=excluded.language,metadata=public.user_policy_acknowledgements.metadata||excluded.metadata,updated_at=now()
  returning * into v_row;
  return jsonb_build_object('policy_key',v_row.policy_key,'version',v_row.policy_version,'accepted',v_row.accepted,'accepted_at',v_row.accepted_at,'revoked_at',v_row.revoked_at);
end;
$function$;
revoke all on function public.record_my_policy_acknowledgement(text,boolean,jsonb) from public,anon;
grant execute on function public.record_my_policy_acknowledgement(text,boolean,jsonb) to authenticated,service_role;

create or replace function public.has_current_policy_acknowledgement(p_policy_key text)
returns boolean
language sql
stable
security invoker
set search_path to ''
as $function$
  select exists(
    select 1
    from public.policy_documents d
    join public.user_policy_acknowledgements a on a.policy_key=d.policy_key and a.policy_version=d.version
    where d.policy_key=p_policy_key and d.status='active' and a.user_id=(select auth.uid()) and a.accepted=true and a.revoked_at is null
  );
$function$;
grant execute on function public.has_current_policy_acknowledgement(text) to authenticated,service_role;

create or replace function public.get_my_policy_status()
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'policy_key',d.policy_key,'version',d.version,'title',d.title,'required_for_access',d.required_for_access,'explicit_consent',d.explicit_consent,'revocable',d.revocable,'scope',d.scope,
    'accepted',coalesce(a.accepted,false) and a.revoked_at is null,'accepted_at',a.accepted_at,'revoked_at',a.revoked_at
  ) order by d.policy_key),'[]'::jsonb)
  from public.policy_documents d
  left join public.user_policy_acknowledgements a on a.policy_key=d.policy_key and a.policy_version=d.version and a.user_id=(select auth.uid())
  where d.status='active';
$function$;
grant execute on function public.get_my_policy_status() to authenticated,service_role;

create table if not exists public.data_subject_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  request_type text not null check (request_type in ('access','export','rectification','erasure','objection','restriction')),
  status text not null default 'pending' check (status in ('pending','in_review','completed','rejected','cancelled')),
  details text,
  response_notes text,
  requested_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  handled_by uuid references public.profiles(id) on delete set null
);
create index if not exists data_subject_requests_user_status_idx on public.data_subject_requests(user_id,status,requested_at desc);
create index if not exists data_subject_requests_status_idx on public.data_subject_requests(status,requested_at);
alter table public.data_subject_requests enable row level security;
revoke all on public.data_subject_requests from public,anon,authenticated;
grant select,insert,update on public.data_subject_requests to authenticated,service_role;
grant delete on public.data_subject_requests to service_role;
drop policy if exists dsr_owner_or_admin_read on public.data_subject_requests;
create policy dsr_owner_or_admin_read on public.data_subject_requests for select to authenticated using (user_id=(select auth.uid()) or private.is_admin_user());
drop policy if exists dsr_owner_insert on public.data_subject_requests;
create policy dsr_owner_insert on public.data_subject_requests for insert to authenticated with check (user_id=(select auth.uid()) and status='pending');
drop policy if exists dsr_owner_cancel on public.data_subject_requests;
create policy dsr_owner_cancel on public.data_subject_requests for update to authenticated using (user_id=(select auth.uid()) and status='pending') with check (user_id=(select auth.uid()) and status='cancelled');
drop policy if exists dsr_admin_update on public.data_subject_requests;
create policy dsr_admin_update on public.data_subject_requests for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());

create or replace function public.request_my_data_subject_action(p_request_type text,p_details text default null)
returns uuid
language plpgsql
security invoker
set search_path to ''
as $function$
declare v_uid uuid := (select auth.uid()); v_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_request_type not in ('access','export','rectification','erasure','objection','restriction') then raise exception 'unsupported data-subject request'; end if;
  if exists(select 1 from public.data_subject_requests where user_id=v_uid and request_type=p_request_type and status in ('pending','in_review')) then raise exception 'a request of this type is already open'; end if;
  insert into public.data_subject_requests(user_id,request_type,details,status) values(v_uid,p_request_type,nullif(trim(coalesce(p_details,'')),''),'pending') returning id into v_id;
  return v_id;
end;
$function$;
revoke all on function public.request_my_data_subject_action(text,text) from public,anon;
grant execute on function public.request_my_data_subject_action(text,text) to authenticated,service_role;

create or replace function public.get_my_portable_data_snapshot()
returns jsonb
language plpgsql
stable
security invoker
set search_path to ''
as $function$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  return jsonb_build_object(
    'generated_at',now(),
    'profile',(select to_jsonb(p) from public.profiles p where p.id=v_uid),
    'education',coalesce((select jsonb_agg(to_jsonb(x)) from public.profile_education x where x.user_id=v_uid),'[]'::jsonb),
    'experience',coalesce((select jsonb_agg(to_jsonb(x)) from public.profile_experience x where x.user_id=v_uid),'[]'::jsonb),
    'projects',coalesce((select jsonb_agg(to_jsonb(x)) from public.profile_projects x where x.user_id=v_uid),'[]'::jsonb),
    'languages',coalesce((select jsonb_agg(to_jsonb(x)) from public.profile_languages x where x.user_id=v_uid),'[]'::jsonb),
    'documents',coalesce((select jsonb_agg(to_jsonb(x)-'file_url') from public.profile_documents x where x.user_id=v_uid),'[]'::jsonb),
    'verified_skills',coalesce((select jsonb_agg(to_jsonb(x)) from public.verified_skills x where x.user_id=v_uid),'[]'::jsonb),
    'career_achievements',coalesce((select jsonb_agg(to_jsonb(x)) from public.career_passport_achievements x where x.user_id=v_uid),'[]'::jsonb),
    'applications',coalesce((select jsonb_agg(to_jsonb(x)) from public.applications x where x.applicant_id=v_uid),'[]'::jsonb),
    'saved_opportunities',coalesce((select jsonb_agg(to_jsonb(x)) from public.saved_opportunities x where x.user_id=v_uid),'[]'::jsonb),
    'career_enrollments',coalesce((select jsonb_agg(to_jsonb(x)) from public.career_path_enrollments x where x.user_id=v_uid),'[]'::jsonb),
    'lesson_progress',coalesce((select jsonb_agg(to_jsonb(x)) from public.student_lesson_progress x where x.user_id=v_uid),'[]'::jsonb),
    'practice_sessions',coalesce((select jsonb_agg(to_jsonb(x)) from public.practice_sessions x where x.user_id=v_uid),'[]'::jsonb),
    'assessment_attempts',coalesce((select jsonb_agg(to_jsonb(x)) from public.assessment_attempts x where x.user_id=v_uid),'[]'::jsonb),
    'freelance_proposals',coalesce((select jsonb_agg(to_jsonb(x)) from public.marketplace_submissions x where x.user_id=v_uid),'[]'::jsonb),
    'freelance_contracts',coalesce((select jsonb_agg(to_jsonb(x)) from public.freelance_contracts x where x.freelancer_id=v_uid),'[]'::jsonb),
    'mentorship_requests',coalesce((select jsonb_agg(to_jsonb(x)) from public.mentorship_requests x where x.mentee_id=v_uid or x.mentor_id=v_uid),'[]'::jsonb),
    'mentorship_sessions',coalesce((select jsonb_agg(to_jsonb(x)) from public.mentorship_sessions x where x.mentee_id=v_uid or x.mentor_id=v_uid),'[]'::jsonb),
    'arena_participation',coalesce((select jsonb_agg(to_jsonb(x)) from public.arena_participants x where x.user_id=v_uid),'[]'::jsonb),
    'arena_rewards',coalesce((select jsonb_agg(to_jsonb(x)) from public.arena_rewards x where x.beneficiary_user_id=v_uid),'[]'::jsonb),
    'earnings_ledger',coalesce((select jsonb_agg(to_jsonb(x)) from public.earnings_ledger x where x.user_id=v_uid),'[]'::jsonb),
    'notifications',coalesce((select jsonb_agg(to_jsonb(x)) from public.notifications x where x.user_id=v_uid),'[]'::jsonb),
    'career_coach_sessions',coalesce((select jsonb_agg(to_jsonb(x)) from public.career_coach_sessions x where x.user_id=v_uid),'[]'::jsonb),
    'policy_acknowledgements',coalesce((select jsonb_agg(to_jsonb(x)) from public.user_policy_acknowledgements x where x.user_id=v_uid),'[]'::jsonb),
    'data_subject_requests',coalesce((select jsonb_agg(to_jsonb(x)) from public.data_subject_requests x where x.user_id=v_uid),'[]'::jsonb)
  );
end;
$function$;
revoke all on function public.get_my_portable_data_snapshot() from public,anon;
grant execute on function public.get_my_portable_data_snapshot() to authenticated,service_role;

create or replace function private.enforce_proctoring_consent()
returns trigger
language plpgsql
security invoker
set search_path to ''
as $function$
declare v_proctored boolean;
begin
  select is_proctored into v_proctored from public.skill_assessments where id=new.assessment_id;
  if coalesce(v_proctored,false) and not public.has_current_policy_acknowledgement('proctoring') then
    raise exception 'proctoring consent is required before starting this assessment';
  end if;
  return new;
end;
$function$;
drop trigger if exists trg_require_proctoring_consent on public.assessment_attempts;
create trigger trg_require_proctoring_consent before insert on public.assessment_attempts for each row execute function private.enforce_proctoring_consent();

drop policy if exists mela_adult_work_submission_insert on public.marketplace_submissions;
create policy mela_adult_work_submission_insert on public.marketplace_submissions as restrictive for insert to authenticated with check (public.has_current_policy_acknowledgement('adult_work_eligibility'));
drop policy if exists mela_adult_work_submission_update on public.marketplace_submissions;
create policy mela_adult_work_submission_update on public.marketplace_submissions as restrictive for update to authenticated using (public.has_current_policy_acknowledgement('adult_work_eligibility')) with check (public.has_current_policy_acknowledgement('adult_work_eligibility'));
;

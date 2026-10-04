-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814162545
alter table public.assessment_attempts add column if not exists language_code text not null default 'en';

do $$ begin
  if not exists (select 1 from pg_constraint where conname='assessment_attempts_language_code_check' and conrelid='public.assessment_attempts'::regclass) then
    alter table public.assessment_attempts add constraint assessment_attempts_language_code_check check (language_code in ('en','am','om','ti','so'));
  end if;
end $$;

alter table public.assessment_language_certifications add column if not exists certification_metadata jsonb not null default '{}'::jsonb;

create table if not exists public.assessment_language_reviewer_qualifications (
  reviewer_id uuid not null references public.profiles(id) on delete cascade,
  language_code text not null references public.platform_languages(language_code) on update cascade on delete restrict,
  qualified boolean not null default false,
  qualification_notes text,
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (reviewer_id, language_code),
  constraint assessment_language_reviewer_no_english check (language_code in ('am','om','ti','so'))
);

create table if not exists public.assessment_language_review_assignments (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references public.skill_assessments(id) on delete cascade,
  language_code text not null references public.platform_languages(language_code) on update cascade on delete restrict,
  reviewer_id uuid not null references public.profiles(id) on delete cascade,
  assigned_by uuid references public.profiles(id) on delete set null,
  status text not null default 'assigned' check (status in ('assigned','in_review','approved','changes_required','cancelled')),
  reviewer_notes text,
  assigned_at timestamptz not null default now(),
  submitted_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (assessment_id, language_code, reviewer_id),
  constraint assessment_language_review_non_english check (language_code in ('am','om','ti','so'))
);

create table if not exists public.assessment_question_translations (
  question_id uuid not null references public.assessment_questions(id) on delete cascade,
  assessment_id uuid not null references public.skill_assessments(id) on delete cascade,
  language_code text not null references public.platform_languages(language_code) on update cascade on delete restrict,
  prompt text not null,
  choices jsonb not null default '[]'::jsonb,
  competency text,
  source_version integer not null,
  translation_version integer not null default 1,
  translation_model text,
  status text not null default 'draft' check (status in ('draft','in_review','reviewed','certified','rejected')),
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (question_id, language_code),
  unique (assessment_id, language_code, question_id),
  constraint assessment_question_translation_non_english check (language_code in ('am','om','ti','so')),
  constraint assessment_question_translation_choices_array check (jsonb_typeof(choices)='array')
);

create index if not exists assessment_language_review_assignments_reviewer_idx on public.assessment_language_review_assignments(reviewer_id,status,language_code);
create index if not exists assessment_question_translations_assessment_lang_idx on public.assessment_question_translations(assessment_id,language_code,status);

alter table public.assessment_language_reviewer_qualifications enable row level security;
alter table public.assessment_language_review_assignments enable row level security;
alter table public.assessment_question_translations enable row level security;

revoke all on table public.assessment_language_reviewer_qualifications from anon, authenticated;
revoke all on table public.assessment_language_review_assignments from anon, authenticated;
revoke all on table public.assessment_question_translations from anon, authenticated;

grant select on table public.assessment_language_review_assignments to authenticated;

create policy assessment_review_assignments_read_own_or_admin
on public.assessment_language_review_assignments
for select to authenticated
using (reviewer_id=(select auth.uid()) or private.is_admin_user());

create or replace function private.resolve_mela_language_code(p_value text)
returns text
language sql
immutable
set search_path=''
as $$
  select case coalesce(p_value,'English')
    when 'English' then 'en' when 'Amharic' then 'am' when 'Afaan Oromo' then 'om' when 'Tigrinya' then 'ti' when 'Somali' then 'so'
    when 'en' then 'en' when 'am' then 'am' when 'om' then 'om' when 'ti' then 'ti' when 'so' then 'so'
    else 'en' end;
$$;

create or replace function private.prepare_assessment_attempt()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $$
declare
  v_max_attempts integer;
  v_proctored boolean;
  v_cooldown integer;
  v_previous_count integer;
  v_last_started timestamptz;
  v_language text;
begin
  select max_attempts, is_proctored, cooldown_hours
    into v_max_attempts, v_proctored, v_cooldown
  from public.skill_assessments
  where id = new.assessment_id and status = 'published';
  if not found then raise exception 'Assessment is not published'; end if;

  if (select auth.uid()) is not null and new.user_id is distinct from (select auth.uid()) and not private.is_admin_user() then
    raise exception 'Assessment attempt user mismatch';
  end if;

  select private.resolve_mela_language_code(p.preferred_language) into v_language
  from public.profiles p where p.id=new.user_id;
  if v_language is null then v_language:='en'; end if;

  if not exists(
    select 1 from public.assessment_language_certifications c
    where c.assessment_id=new.assessment_id and c.language_code=v_language and c.status='certified'
  ) then
    raise exception 'Assessment language % is not certified for credential use', v_language;
  end if;

  select count(*)::integer, max(started_at)
    into v_previous_count, v_last_started
  from public.assessment_attempts
  where assessment_id = new.assessment_id and user_id = new.user_id;
  if v_previous_count >= v_max_attempts then raise exception 'Maximum attempts reached'; end if;
  if v_cooldown > 0 and v_last_started is not null and v_last_started > now() - make_interval(hours => v_cooldown) then
    raise exception 'Assessment cooldown is still active';
  end if;

  new.language_code := v_language;
  new.attempt_no := v_previous_count + 1;
  new.status := 'in_progress';
  new.started_at := now();
  new.submitted_at := null;
  new.duration_seconds := null;
  new.score := null;
  new.passed := null;
  new.proctored := v_proctored;
  new.integrity_score := null;
  new.proctor_status := case when v_proctored then 'pending' else 'not_required' end;
  new.reviewed_at := null;
  new.metadata := jsonb_build_object('language_code',v_language);
  return new;
end;
$$;

create or replace function private.populate_assessment_attempt_questions()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $$
declare
  v_question_count integer;
  v_available integer;
begin
  select question_count into v_question_count from public.skill_assessments where id=new.assessment_id;
  select count(*)::integer into v_available
  from public.assessment_questions
  where assessment_id=new.assessment_id and active=true and language_code='en';
  if v_available < v_question_count then raise exception 'Assessment does not have enough active source questions'; end if;

  insert into public.assessment_attempt_questions(attempt_id,question_id,position,points_snapshot)
  select new.id,q.id,row_number() over ()::integer,q.points
  from (
    select id,points
    from public.assessment_questions
    where assessment_id=new.assessment_id and active=true and language_code='en'
    order by random()
    limit v_question_count
  ) q;
  return new;
end;
$$;

create or replace function private.get_assessment_attempt_questions_localized(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=(select auth.uid());
  v_attempt public.assessment_attempts;
  v_rows jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select * into v_attempt from public.assessment_attempts where id=p_attempt_id;
  if not found then raise exception 'Assessment attempt not found'; end if;
  if v_attempt.user_id<>v_uid and not private.is_admin_user() then raise exception 'Assessment attempt access denied'; end if;
  if not exists(select 1 from public.assessment_language_certifications c where c.assessment_id=v_attempt.assessment_id and c.language_code=v_attempt.language_code and c.status='certified') then
    raise exception 'Assessment language is not certified';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'question_id',q.id,
    'position',aq.position,
    'prompt',case when v_attempt.language_code='en' then q.prompt else t.prompt end,
    'choices',case when v_attempt.language_code='en' then q.choices else t.choices end,
    'competency',case when v_attempt.language_code='en' then q.competency else coalesce(t.competency,q.competency) end,
    'difficulty',q.difficulty,
    'language_code',v_attempt.language_code
  ) order by aq.position),'[]'::jsonb)
  into v_rows
  from public.assessment_attempt_questions aq
  join public.assessment_questions q on q.id=aq.question_id
  left join public.assessment_question_translations t on t.question_id=q.id and t.language_code=v_attempt.language_code and t.source_version=q.version
  where aq.attempt_id=p_attempt_id
    and (v_attempt.language_code='en' or t.question_id is not null);

  if jsonb_array_length(v_rows)<>(select count(*) from public.assessment_attempt_questions where attempt_id=p_attempt_id) then
    raise exception 'Certified assessment translation bundle is incomplete or stale';
  end if;
  return v_rows;
end;
$$;

create or replace function private.admin_qualify_assessment_language_reviewer(p_reviewer_id uuid,p_language_code text,p_qualified boolean,p_notes text default null)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
  if p_language_code not in ('am','om','ti','so') then raise exception 'unsupported reviewer language'; end if;
  if not exists(select 1 from public.profiles where id=p_reviewer_id) then raise exception 'reviewer profile not found'; end if;
  insert into public.assessment_language_reviewer_qualifications(reviewer_id,language_code,qualified,qualification_notes,approved_by,approved_at,updated_at)
  values(p_reviewer_id,p_language_code,p_qualified,nullif(trim(coalesce(p_notes,'')),''),v_uid,case when p_qualified then now() else null end,now())
  on conflict(reviewer_id,language_code) do update set qualified=excluded.qualified,qualification_notes=excluded.qualification_notes,approved_by=excluded.approved_by,approved_at=excluded.approved_at,updated_at=now();
end $$;

create or replace function private.admin_assign_assessment_language_reviewer(p_assessment_id uuid,p_language_code text,p_reviewer_id uuid)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_id uuid; begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
  if p_language_code not in ('am','om','ti','so') then raise exception 'unsupported review language'; end if;
  if not exists(select 1 from public.skill_assessments where id=p_assessment_id and status='published') then raise exception 'published assessment not found'; end if;
  if not exists(select 1 from public.assessment_language_reviewer_qualifications where reviewer_id=p_reviewer_id and language_code=p_language_code and qualified=true) then raise exception 'reviewer is not qualified for this language'; end if;
  insert into public.assessment_language_review_assignments(assessment_id,language_code,reviewer_id,assigned_by,status,assigned_at,updated_at)
  values(p_assessment_id,p_language_code,p_reviewer_id,v_uid,'assigned',now(),now())
  on conflict(assessment_id,language_code,reviewer_id) do update set assigned_by=v_uid,status='assigned',reviewer_notes=null,submitted_at=null,assigned_at=now(),updated_at=now()
  returning id into v_id;
  update public.assessment_language_certifications set status='in_review',certified_at=null,updated_at=now() where assessment_id=p_assessment_id and language_code=p_language_code and status<>'certified';
  return v_id;
end $$;

create or replace function private.get_my_assessment_language_review(p_assessment_id uuid,p_language_code text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_assignment public.assessment_language_review_assignments; v_result jsonb; begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select * into v_assignment from public.assessment_language_review_assignments
  where assessment_id=p_assessment_id and language_code=p_language_code and reviewer_id=v_uid and status<>'cancelled'
  order by assigned_at desc limit 1;
  if not found and not private.is_admin_user() then raise exception 'language review assignment required'; end if;
  if found and v_assignment.status='assigned' then update public.assessment_language_review_assignments set status='in_review',updated_at=now() where id=v_assignment.id; end if;
  select jsonb_build_object(
    'assessment',(select to_jsonb(a) - 'created_at' - 'updated_at' from public.skill_assessments a where a.id=p_assessment_id),
    'language_code',p_language_code,
    'assignment',case when v_assignment.id is null then null else to_jsonb(v_assignment) end,
    'certification',(select to_jsonb(c) from public.assessment_language_certifications c where c.assessment_id=p_assessment_id and c.language_code=p_language_code),
    'questions',coalesce((select jsonb_agg(jsonb_build_object(
       'question_id',q.id,'question_order',q.question_order,'source_prompt',q.prompt,'source_choices',q.choices,'source_competency',q.competency,'source_version',q.version,
       'translated_prompt',t.prompt,'translated_choices',t.choices,'translated_competency',t.competency,'translation_status',t.status,'translation_model',t.translation_model
    ) order by q.question_order)
    from public.assessment_questions q
    left join public.assessment_question_translations t on t.question_id=q.id and t.language_code=p_language_code
    where q.assessment_id=p_assessment_id and q.active=true and q.language_code='en'),'[]'::jsonb)
  ) into v_result;
  return v_result;
end $$;

create or replace function private.submit_assessment_language_review(p_assessment_id uuid,p_language_code text,p_decision text,p_notes text default null)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_status text; v_source_count int; v_translation_count int; begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if p_decision not in ('approved','changes_required') then raise exception 'invalid review decision'; end if;
  if not exists(select 1 from public.assessment_language_review_assignments where assessment_id=p_assessment_id and language_code=p_language_code and reviewer_id=v_uid and status in ('assigned','in_review','approved','changes_required')) then raise exception 'language review assignment required'; end if;
  if not exists(select 1 from public.assessment_language_reviewer_qualifications where reviewer_id=v_uid and language_code=p_language_code and qualified=true) then raise exception 'active reviewer qualification required'; end if;
  select count(*) into v_source_count from public.assessment_questions where assessment_id=p_assessment_id and active=true and language_code='en';
  select count(*) into v_translation_count from public.assessment_question_translations t join public.assessment_questions q on q.id=t.question_id where t.assessment_id=p_assessment_id and t.language_code=p_language_code and t.source_version=q.version and q.active=true and q.language_code='en';
  if v_translation_count<>v_source_count then raise exception 'translation bundle is incomplete or stale'; end if;
  v_status:=p_decision;
  update public.assessment_language_review_assignments set status=v_status,reviewer_notes=nullif(trim(coalesce(p_notes,'')),''),submitted_at=now(),updated_at=now()
  where assessment_id=p_assessment_id and language_code=p_language_code and reviewer_id=v_uid;
  update public.assessment_question_translations set status=case when p_decision='approved' then 'reviewed' else 'rejected' end,updated_at=now() where assessment_id=p_assessment_id and language_code=p_language_code;
  if p_decision='changes_required' then update public.assessment_language_certifications set status='rejected',certified_at=null,updated_at=now() where assessment_id=p_assessment_id and language_code=p_language_code; end if;
end $$;

create or replace function private.admin_certify_assessment_language(p_assessment_id uuid,p_language_code text,p_notes text default null)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_approved int; v_source_count int; v_translation_count int; v_reviewers jsonb; begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
  if p_language_code not in ('am','om','ti','so') then raise exception 'only translated assessment languages use this certification workflow'; end if;
  select count(distinct a.reviewer_id),coalesce(jsonb_agg(distinct a.reviewer_id),'[]'::jsonb)
    into v_approved,v_reviewers
  from public.assessment_language_review_assignments a
  join public.assessment_language_reviewer_qualifications q on q.reviewer_id=a.reviewer_id and q.language_code=a.language_code and q.qualified=true
  where a.assessment_id=p_assessment_id and a.language_code=p_language_code and a.status='approved';
  if v_approved<2 then raise exception 'two independent qualified reviewer approvals are required'; end if;
  select count(*) into v_source_count from public.assessment_questions where assessment_id=p_assessment_id and active=true and language_code='en';
  select count(*) into v_translation_count from public.assessment_question_translations t join public.assessment_questions q on q.id=t.question_id where t.assessment_id=p_assessment_id and t.language_code=p_language_code and t.source_version=q.version and q.active=true and q.language_code='en';
  if v_translation_count<>v_source_count then raise exception 'translation bundle is incomplete or stale'; end if;
  update public.assessment_question_translations set status='certified',updated_at=now() where assessment_id=p_assessment_id and language_code=p_language_code;
  update public.assessment_language_certifications
     set status='certified',reviewer_notes=coalesce(nullif(trim(coalesce(p_notes,'')),''),'Certified after two independent qualified bilingual reviews.'),reviewed_by=v_uid,certified_at=now(),certification_metadata=jsonb_build_object('certified_by',v_uid,'reviewers',v_reviewers,'reviewer_count',v_approved),updated_at=now()
   where assessment_id=p_assessment_id and language_code=p_language_code;
  if not found then raise exception 'assessment language certification record not found'; end if;
end $$;

create or replace function public.get_assessment_attempt_questions_localized(p_attempt_id uuid)
returns jsonb language sql set search_path='' as $$ select private.get_assessment_attempt_questions_localized(p_attempt_id); $$;
create or replace function public.admin_qualify_assessment_language_reviewer(p_reviewer_id uuid,p_language_code text,p_qualified boolean,p_notes text default null)
returns void language sql set search_path='' as $$ select private.admin_qualify_assessment_language_reviewer(p_reviewer_id,p_language_code,p_qualified,p_notes); $$;
create or replace function public.admin_assign_assessment_language_reviewer(p_assessment_id uuid,p_language_code text,p_reviewer_id uuid)
returns uuid language sql set search_path='' as $$ select private.admin_assign_assessment_language_reviewer(p_assessment_id,p_language_code,p_reviewer_id); $$;
create or replace function public.get_my_assessment_language_review(p_assessment_id uuid,p_language_code text)
returns jsonb language sql set search_path='' as $$ select private.get_my_assessment_language_review(p_assessment_id,p_language_code); $$;
create or replace function public.submit_assessment_language_review(p_assessment_id uuid,p_language_code text,p_decision text,p_notes text default null)
returns void language sql set search_path='' as $$ select private.submit_assessment_language_review(p_assessment_id,p_language_code,p_decision,p_notes); $$;
create or replace function public.admin_certify_assessment_language(p_assessment_id uuid,p_language_code text,p_notes text default null)
returns void language sql set search_path='' as $$ select private.admin_certify_assessment_language(p_assessment_id,p_language_code,p_notes); $$;

revoke execute on function private.get_assessment_attempt_questions_localized(uuid) from public,anon;
revoke execute on function private.admin_qualify_assessment_language_reviewer(uuid,text,boolean,text) from public,anon;
revoke execute on function private.admin_assign_assessment_language_reviewer(uuid,text,uuid) from public,anon;
revoke execute on function private.get_my_assessment_language_review(uuid,text) from public,anon;
revoke execute on function private.submit_assessment_language_review(uuid,text,text,text) from public,anon;
revoke execute on function private.admin_certify_assessment_language(uuid,text,text) from public,anon;
grant execute on function private.get_assessment_attempt_questions_localized(uuid) to authenticated,service_role;
grant execute on function private.admin_qualify_assessment_language_reviewer(uuid,text,boolean,text) to authenticated,service_role;
grant execute on function private.admin_assign_assessment_language_reviewer(uuid,text,uuid) to authenticated,service_role;
grant execute on function private.get_my_assessment_language_review(uuid,text) to authenticated,service_role;
grant execute on function private.submit_assessment_language_review(uuid,text,text,text) to authenticated,service_role;
grant execute on function private.admin_certify_assessment_language(uuid,text,text) to authenticated,service_role;

revoke execute on function public.get_assessment_attempt_questions_localized(uuid) from public,anon;
revoke execute on function public.admin_qualify_assessment_language_reviewer(uuid,text,boolean,text) from public,anon;
revoke execute on function public.admin_assign_assessment_language_reviewer(uuid,text,uuid) from public,anon;
revoke execute on function public.get_my_assessment_language_review(uuid,text) from public,anon;
revoke execute on function public.submit_assessment_language_review(uuid,text,text,text) from public,anon;
revoke execute on function public.admin_certify_assessment_language(uuid,text,text) from public,anon;
grant execute on function public.get_assessment_attempt_questions_localized(uuid) to authenticated;
grant execute on function public.admin_qualify_assessment_language_reviewer(uuid,text,boolean,text) to authenticated;
grant execute on function public.admin_assign_assessment_language_reviewer(uuid,text,uuid) to authenticated;
grant execute on function public.get_my_assessment_language_review(uuid,text) to authenticated;
grant execute on function public.submit_assessment_language_review(uuid,text,text,text) to authenticated;
grant execute on function public.admin_certify_assessment_language(uuid,text,text) to authenticated;

;

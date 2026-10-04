-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812204817
-- Step 2: complete assessment engine

alter table public.skill_assessments
  add column if not exists instructions text,
  add column if not exists question_count integer not null default 10,
  add column if not exists shuffle_questions boolean not null default true,
  add column if not exists shuffle_choices boolean not null default true,
  add column if not exists cooldown_hours integer not null default 0;

do $$ begin
  alter table public.skill_assessments add constraint skill_assessments_question_count_chk check (question_count between 1 and 100);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.skill_assessments add constraint skill_assessments_cooldown_hours_chk check (cooldown_hours between 0 and 8760);
exception when duplicate_object then null; end $$;

alter table public.assessment_questions
  add column if not exists competency text,
  add column if not exists difficulty smallint not null default 1,
  add column if not exists language_code text not null default 'en',
  add column if not exists version integer not null default 1,
  add column if not exists updated_at timestamptz not null default now();

do $$ begin
  alter table public.assessment_questions add constraint assessment_questions_difficulty_chk check (difficulty between 1 and 3);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.assessment_questions add constraint assessment_questions_version_chk check (version >= 1);
exception when duplicate_object then null; end $$;

alter table public.assessment_attempts
  add column if not exists proctor_status text not null default 'not_required',
  add column if not exists reviewed_at timestamptz;

alter table public.assessment_attempts drop constraint if exists assessment_attempt_status_chk;
alter table public.assessment_attempts
  add constraint assessment_attempt_status_chk check (status in ('in_progress','submitted','graded','review_required','void'));

do $$ begin
  alter table public.assessment_attempts add constraint assessment_attempt_proctor_status_chk check (proctor_status in ('not_required','pending','clear','flagged'));
exception when duplicate_object then null; end $$;

create table if not exists public.assessment_attempt_questions (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.assessment_attempts(id) on delete cascade,
  question_id uuid not null references public.assessment_questions(id) on delete restrict,
  position integer not null,
  points_snapshot numeric not null default 1,
  created_at timestamptz not null default now(),
  unique (attempt_id, question_id),
  unique (attempt_id, position),
  check (position > 0),
  check (points_snapshot > 0)
);

alter table public.assessment_attempt_questions enable row level security;

create index if not exists assessment_attempt_questions_attempt_idx on public.assessment_attempt_questions(attempt_id);
create index if not exists assessment_attempt_questions_question_idx on public.assessment_attempt_questions(question_id);
create index if not exists assessment_responses_question_idx on public.assessment_responses(question_id);
create index if not exists assessment_attempts_user_assessment_idx on public.assessment_attempts(user_id, assessment_id, started_at desc);
create unique index if not exists assessment_attempts_one_in_progress_idx
  on public.assessment_attempts(user_id, assessment_id)
  where status = 'in_progress';
create unique index if not exists verified_skills_source_unique_idx
  on public.verified_skills(user_id, skill_name, verification_source);

-- Do not expose question banks anonymously.
revoke all on table public.assessment_questions from anon;
revoke all on table public.assessment_attempt_questions from anon;
revoke all on table public.assessment_attempts from anon;
revoke all on table public.assessment_responses from anon;

grant select on public.assessment_questions to authenticated;
grant select on public.assessment_attempt_questions to authenticated;
grant select on public.assessment_attempts to authenticated;
grant select on public.assessment_responses to authenticated;
grant select, insert, update, delete on public.assessment_attempt_questions to service_role;
grant select, insert, update, delete on public.assessment_questions to service_role;
grant select, insert, update, delete on public.assessment_attempts to service_role;
grant select, insert, update, delete on public.assessment_responses to service_role;

-- Lock browser writes to only fields a student should control.
revoke insert, update on public.assessment_attempts from authenticated;
grant insert (assessment_id, user_id) on public.assessment_attempts to authenticated;
grant update (status, duration_seconds) on public.assessment_attempts to authenticated;

revoke insert, update on public.assessment_responses from authenticated;
grant insert (attempt_id, question_id, response) on public.assessment_responses to authenticated;
grant update (response) on public.assessment_responses to authenticated;

-- Replace question visibility: only selected questions for the user's own attempt, plus admins.
drop policy if exists "Published questions public" on public.assessment_questions;
drop policy if exists "Questions readable for active attempts" on public.assessment_questions;
create policy "Questions readable for active attempts"
on public.assessment_questions for select
to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'::public.user_role
  )
  or exists (
    select 1
    from public.assessment_attempt_questions aq
    join public.assessment_attempts a on a.id = aq.attempt_id
    where aq.question_id = assessment_questions.id
      and a.user_id = (select auth.uid())
      and a.status in ('in_progress','submitted','graded','review_required')
  )
);

-- Attempt question set is private to the attempt owner/admin.
drop policy if exists "Attempt questions readable by owner" on public.assessment_attempt_questions;
create policy "Attempt questions readable by owner"
on public.assessment_attempt_questions for select
to authenticated
using (
  exists (
    select 1 from public.assessment_attempts a
    where a.id = assessment_attempt_questions.attempt_id
      and (
        a.user_id = (select auth.uid())
        or exists (
          select 1 from public.profiles p
          where p.id = (select auth.uid()) and p.role = 'admin'::public.user_role
        )
      )
  )
);

-- Fix the previous max-attempt bug and enforce student-only attempt creation.
drop policy if exists "Students start own attempt" on public.assessment_attempts;
create policy "Students start own attempt"
on public.assessment_attempts for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and status = 'in_progress'
  and score is null and passed is null and integrity_score is null
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'student'::public.user_role
  )
  and exists (
    select 1 from public.skill_assessments sa
    where sa.id = assessment_attempts.assessment_id
      and sa.status = 'published'
      and assessment_attempts.proctored = sa.is_proctored
      and assessment_attempts.attempt_no between 1 and sa.max_attempts
  )
);

drop policy if exists "Students submit own attempt" on public.assessment_attempts;
create policy "Students submit own attempt"
on public.assessment_attempts for update
to authenticated
using (
  user_id = (select auth.uid()) and status = 'in_progress'
)
with check (
  user_id = (select auth.uid())
  and status in ('in_progress','submitted')
  and score is null and passed is null and integrity_score is null
);

-- Responses must belong to the frozen question set for the attempt.
drop policy if exists "Responses insert by attempt owner" on public.assessment_responses;
create policy "Responses insert by attempt owner"
on public.assessment_responses for insert
to authenticated
with check (
  exists (
    select 1
    from public.assessment_attempts a
    join public.assessment_attempt_questions aq on aq.attempt_id = a.id
    where a.id = assessment_responses.attempt_id
      and aq.question_id = assessment_responses.question_id
      and a.user_id = (select auth.uid())
      and a.status = 'in_progress'
  )
);

drop policy if exists "Responses update by attempt owner" on public.assessment_responses;
create policy "Responses update by attempt owner"
on public.assessment_responses for update
to authenticated
using (
  exists (
    select 1 from public.assessment_attempts a
    where a.id = assessment_responses.attempt_id
      and a.user_id = (select auth.uid())
      and a.status = 'in_progress'
  )
)
with check (
  exists (
    select 1
    from public.assessment_attempts a
    join public.assessment_attempt_questions aq on aq.attempt_id = a.id
    where a.id = assessment_responses.attempt_id
      and aq.question_id = assessment_responses.question_id
      and a.user_id = (select auth.uid())
      and a.status = 'in_progress'
  )
);

-- Prepare attempts server-side so attempt_no/proctor fields cannot be spoofed.
create or replace function private.prepare_assessment_attempt()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_max_attempts integer;
  v_proctored boolean;
  v_cooldown integer;
  v_previous_count integer;
  v_last_started timestamptz;
begin
  select max_attempts, is_proctored, cooldown_hours
    into v_max_attempts, v_proctored, v_cooldown
  from public.skill_assessments
  where id = new.assessment_id and status = 'published';

  if not found then
    raise exception 'Assessment is not published';
  end if;

  select count(*)::integer, max(started_at)
    into v_previous_count, v_last_started
  from public.assessment_attempts
  where assessment_id = new.assessment_id
    and user_id = new.user_id;

  if v_previous_count >= v_max_attempts then
    raise exception 'Maximum attempts reached';
  end if;

  if v_cooldown > 0 and v_last_started is not null
     and v_last_started > now() - make_interval(hours => v_cooldown) then
    raise exception 'Assessment cooldown is still active';
  end if;

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
  new.metadata := '{}'::jsonb;
  return new;
end;
$$;
revoke all on function private.prepare_assessment_attempt() from public, anon, authenticated;

drop trigger if exists trg_prepare_assessment_attempt on public.assessment_attempts;
create trigger trg_prepare_assessment_attempt
before insert on public.assessment_attempts
for each row execute function private.prepare_assessment_attempt();

-- Freeze the exact questions for each attempt.
create or replace function private.populate_assessment_attempt_questions()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_question_count integer;
  v_available integer;
begin
  select question_count into v_question_count
  from public.skill_assessments where id = new.assessment_id;

  select count(*)::integer into v_available
  from public.assessment_questions
  where assessment_id = new.assessment_id and active = true;

  if v_available < v_question_count then
    raise exception 'Assessment does not have enough active questions';
  end if;

  insert into public.assessment_attempt_questions(attempt_id, question_id, position, points_snapshot)
  select new.id, q.id, row_number() over ()::integer, q.points
  from (
    select id, points
    from public.assessment_questions
    where assessment_id = new.assessment_id and active = true
    order by random()
    limit v_question_count
  ) q;

  return new;
end;
$$;
revoke all on function private.populate_assessment_attempt_questions() from public, anon, authenticated;

drop trigger if exists trg_populate_assessment_attempt_questions on public.assessment_attempts;
create trigger trg_populate_assessment_attempt_questions
after insert on public.assessment_attempts
for each row execute function private.populate_assessment_attempt_questions();

-- Keep answer timestamps server-controlled.
create or replace function private.touch_assessment_response()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  new.answered_at := now();
  return new;
end;
$$;
revoke all on function private.touch_assessment_response() from public, anon, authenticated;

drop trigger if exists trg_touch_assessment_response on public.assessment_responses;
create trigger trg_touch_assessment_response
before insert or update on public.assessment_responses
for each row execute function private.touch_assessment_response();

-- Internal credential issuer, called only by trusted triggers.
create or replace function private.issue_assessment_verified_skill(p_attempt_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_user_id uuid;
  v_score numeric;
  v_passed boolean;
  v_proctored boolean;
  v_proctor_status text;
  v_title text;
  v_category public.launch_category;
  v_skill_name text;
  v_source text;
  v_level text;
begin
  select a.user_id, a.score, a.passed, a.proctored, a.proctor_status,
         sa.title, sa.category, s.name
  into v_user_id, v_score, v_passed, v_proctored, v_proctor_status,
       v_title, v_category, v_skill_name
  from public.assessment_attempts a
  join public.skill_assessments sa on sa.id = a.assessment_id
  left join public.skills s on s.id = sa.skill_id
  where a.id = p_attempt_id;

  if coalesce(v_passed,false) = false or v_skill_name is null then return; end if;
  if v_proctored and v_proctor_status <> 'clear' then return; end if;

  v_source := 'Mela assessment: ' || v_title;
  v_level := case when v_score >= 90 then 'Advanced'
                  when v_score >= 80 then 'Proficient'
                  else 'Verified' end;

  insert into public.verified_skills(user_id, skill_name, category, level, score, verified, verification_source, issued_at)
  values (v_user_id, v_skill_name, v_category, v_level, round(v_score,1)::text || '%', true, v_source, now())
  on conflict (user_id, skill_name, verification_source)
  do update set level = excluded.level,
                score = excluded.score,
                verified = true,
                issued_at = excluded.issued_at;
end;
$$;
revoke all on function private.issue_assessment_verified_skill(uuid) from public, anon, authenticated;

-- Grade automatically after the student submits. Correct answers never leave private schema.
create or replace function private.grade_assessment_attempt()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_total numeric;
  v_earned numeric;
  v_score numeric;
  v_pass_score integer;
  v_passed boolean;
  v_has_clear_proctor boolean;
begin
  if old.status = 'in_progress' and new.status = 'submitted' then
    select coalesce(sum(aq.points_snapshot),0),
           coalesce(sum(case when r.response = k.correct_answer then aq.points_snapshot else 0 end),0)
      into v_total, v_earned
    from public.assessment_attempt_questions aq
    left join public.assessment_responses r
      on r.attempt_id = aq.attempt_id and r.question_id = aq.question_id
    left join private.assessment_answer_keys k on k.question_id = aq.question_id
    where aq.attempt_id = new.id;

    if v_total <= 0 then
      raise exception 'Attempt has no questions to grade';
    end if;

    select pass_score into v_pass_score
    from public.skill_assessments where id = new.assessment_id;

    v_score := round((v_earned / v_total) * 100, 2);
    v_passed := v_score >= v_pass_score;

    select exists (
      select 1 from public.proctor_audit_logs l
      where l.attempt_id = new.id
        and l.event_type = 'session_summary'
        and coalesce(l.flagged,false) = false
        and coalesce(l.face_detection_confidence,1) >= 0.70
        and coalesce(l.tab_switch_count,0) <= 3
    ) into v_has_clear_proctor;

    update public.assessment_attempts
    set submitted_at = now(),
        score = v_score,
        passed = v_passed,
        proctor_status = case
          when not new.proctored then 'not_required'
          when v_has_clear_proctor then 'clear'
          else 'pending'
        end,
        status = case
          when not new.proctored then 'graded'
          when v_has_clear_proctor then 'graded'
          else 'review_required'
        end,
        reviewed_at = case when (not new.proctored or v_has_clear_proctor) then now() else null end
    where id = new.id;

    perform private.issue_assessment_verified_skill(new.id);
  end if;
  return new;
end;
$$;
revoke all on function private.grade_assessment_attempt() from public, anon, authenticated;

drop trigger if exists trg_grade_assessment_attempt on public.assessment_attempts;
create trigger trg_grade_assessment_attempt
after update of status on public.assessment_attempts
for each row
when (old.status is distinct from new.status)
execute function private.grade_assessment_attempt();

-- Process a trusted final proctor summary and release a credential only when integrity is clear.
create or replace function private.process_proctor_session_summary()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_integrity numeric;
  v_clear boolean;
  v_current_score numeric;
begin
  if new.attempt_id is null or new.event_type <> 'session_summary' then return new; end if;

  v_integrity := greatest(0, least(100,
      coalesce(new.face_detection_confidence,1) * 100
      - least(coalesce(new.tab_switch_count,0) * 5, 30)
  ));
  v_clear := coalesce(new.flagged,false) = false
             and coalesce(new.face_detection_confidence,1) >= 0.70
             and coalesce(new.tab_switch_count,0) <= 3;

  select score into v_current_score from public.assessment_attempts where id = new.attempt_id;

  update public.assessment_attempts
  set integrity_score = v_integrity,
      proctor_status = case when v_clear then 'clear' else 'flagged' end,
      status = case
        when v_current_score is null then status
        when v_clear then 'graded'
        else 'review_required'
      end,
      reviewed_at = now()
  where id = new.attempt_id;

  if v_clear and v_current_score is not null then
    perform private.issue_assessment_verified_skill(new.attempt_id);
  end if;
  return new;
end;
$$;
revoke all on function private.process_proctor_session_summary() from public, anon, authenticated;

drop trigger if exists trg_process_proctor_session_summary on public.proctor_audit_logs;
create trigger trg_process_proctor_session_summary
after insert or update on public.proctor_audit_logs
for each row execute function private.process_proctor_session_summary();
;

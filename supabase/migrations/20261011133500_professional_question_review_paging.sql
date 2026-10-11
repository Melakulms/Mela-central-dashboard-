-- Proposed for staging on the actual MELA database only. Do not run on a
-- project that is not linked to the public MELA app.
-- Only an active, verified teacher with the matching subject AND grade may
-- approve questions. Administrators can verify teachers but cannot impersonate
-- a professional subject reviewer.
create or replace function private.question_reviewer_allowed_v18(p_uid uuid,p_program_key text)
returns boolean language sql stable security definer set search_path='' as $fn$
  select p_uid=(select auth.uid()) and exists (
    select 1
    from public.profiles p
    join public.teacher_profiles t on t.user_id=p.id
    join public.mela_learning_programs lp on lp.program_key=p_program_key
    where p.id=p_uid and p.role::text='teacher' and p.account_status::text='active'
      and (coalesce(p.email_verified,false) or coalesce(p.phone_verified,false))
      and t.verification_status='approved'
      and (lp.subject_key=any(coalesce(t.subjects_taught,'{}'::text[]))
           or lp.subject_title=any(coalesce(t.subjects_taught,'{}'::text[])))
      and (
        (lp.grade_level is not null and (
          lp.grade_level::text=any(coalesce(t.grade_levels,'{}'::text[]))
          or ('Grade '||lp.grade_level::text)=any(coalesce(t.grade_levels,'{}'::text[]))
        ))
        or (lp.grade_level is null and lp.stage_key=any(coalesce(t.grade_levels,'{}'::text[])))
      )
      and (
        exists (
          select 1 from private.educator_review_authorizations a
          where a.user_id=p_uid and a.active
            and (lp.subject_key=any(a.subject_areas) or lp.subject_title=any(a.subject_areas))
        )
        or exists (
          select 1 from public.educator_profiles e
          where e.user_id=p_uid and e.verified and e.active
            and (lp.subject_key=any(coalesce(e.subject_areas,'{}'::text[]))
                 or lp.subject_title=any(coalesce(e.subject_areas,'{}'::text[])))
            and (coalesce(cardinality(e.stage_keys),0)=0 or lp.stage_key=any(e.stage_keys))
        )
      )
  );
$fn$;

create or replace function private.can_review_questions_v18()
returns boolean language sql stable security definer set search_path='' as $fn$
  select (select auth.uid()) is not null and exists (
    select 1 from public.mela_learning_programs lp
    where lp.active and private.question_reviewer_allowed_v18((select auth.uid()),lp.program_key)
  );
$fn$;

-- Index supports the subject-filtered and paginated pending backlog.
create index if not exists mela_question_review_slices_paged_idx
  on private.mela_question_review_slices_v18(program_key,status,slice_number,id);

create or replace function public.get_question_review_queue_page_v39(
  p_program_key text default null,
  p_status text default null,
  p_limit integer default 20,
  p_offset integer default 0
) returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
  v_uid uuid := (select auth.uid());
  v_total bigint;
  v_rows jsonb;
  v_limit int := least(greatest(coalesce(p_limit,20),1),50);
  v_offset int := greatest(coalesce(p_offset,0),0);
begin
  if v_uid is null or not private.can_review_questions_v18()
    then raise exception 'verified, subject-qualified teacher access required' using errcode='42501'; end if;
  if p_status is not null and p_status not in ('pending','assigned','in_review','changes_required','approved')
    then raise exception 'invalid review state'; end if;
  if v_offset > 200000 then raise exception 'review page offset too large'; end if;

  select count(*) into v_total
  from private.mela_question_review_slices_v18 s
  where (p_program_key is null or s.program_key=p_program_key)
    and (p_status is null or s.status=p_status)
    and private.question_reviewer_allowed_v18(v_uid,s.program_key);

  select coalesce(jsonb_agg(jsonb_build_object(
    'slice_id',z.id,'program_key',z.program_key,
    'grade_level',z.grade_level,'subject_title',z.subject_title,
    'slice_number',z.slice_number,'question_count',z.question_count,
    'status',z.status,'assigned_to',z.assigned_to,
    'reviewed_at',z.reviewed_at
  ) order by z.grade_level,z.subject_title,z.slice_number,z.id),'[]'::jsonb)
  into v_rows from (
    select s.id,s.program_key,p.grade_level,p.subject_title,s.slice_number,
      s.question_count,s.status,s.assigned_to,s.reviewed_at
    from private.mela_question_review_slices_v18 s
    join public.mela_learning_programs p on p.program_key=s.program_key
    where (p_program_key is null or s.program_key=p_program_key)
      and (p_status is null or s.status=p_status)
      and private.question_reviewer_allowed_v18(v_uid,s.program_key)
    order by p.grade_level,p.subject_title,s.slice_number,s.id
    limit v_limit offset v_offset
  ) z;
  return jsonb_build_object('items',v_rows,'total_slices',v_total,'limit',v_limit,'offset',v_offset,
    'has_more',v_offset+v_limit<v_total,'generated_at',now());
end $fn$;
revoke all on function public.get_question_review_queue_page_v39(text,text,integer,integer) from public,anon;
grant execute on function public.get_question_review_queue_page_v39(text,text,integer,integer) to authenticated,service_role;

-- Subject-limited progress. A reviewer sees only their authorized subjects.
-- Counting currently approved teacher decisions (not machine validation) avoids
-- claiming that 140,000 questions have been professionally certified.
create or replace function public.get_my_question_review_progress_v39(
  p_program_key text default null
) returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_uid uuid:=(select auth.uid()); v_active bigint; v_in_slices bigint;
v_recorded bigint; v_approved bigint; v_changes bigint; v_slices bigint;
begin
  if v_uid is null or not private.can_review_questions_v18()
    then raise exception 'verified teacher subject access required' using errcode='42501'; end if;
  select count(*) into v_active
  from public.mela_question_bank q
  where q.active and (p_program_key is null or q.program_key=p_program_key)
    and private.question_reviewer_allowed_v18(v_uid,q.program_key);

  select count(*) into v_in_slices
  from private.mela_question_review_slices_v18 s
  cross join lateral unnest(s.question_ids) ids(question_id)
  where (p_program_key is null or s.program_key=p_program_key)
    and private.question_reviewer_allowed_v18(v_uid,s.program_key);

  select count(*) into v_slices from private.mela_question_review_slices_v18 s
  where (p_program_key is null or s.program_key=p_program_key)
    and private.question_reviewer_allowed_v18(v_uid,s.program_key);

  select count(*),
    count(*) filter(where d.decision='approved'),
    count(*) filter(where d.decision='changes_required')
  into v_recorded,v_approved,v_changes
  from private.mela_question_review_decisions_v18 d
  join private.mela_question_review_slices_v18 s on s.id=d.slice_id
  join public.profiles p on p.id=d.reviewer_id and p.role::text='teacher'
  join public.teacher_profiles t on t.user_id=d.reviewer_id and t.verification_status='approved'
  where (p_program_key is null or s.program_key=p_program_key)
    and private.question_reviewer_allowed_v18(v_uid,s.program_key);

  return jsonb_build_object(
    'active_questions_in_authorized_subjects',v_active,
    'question_entries_in_review_slices',v_in_slices,
    'question_review_slices',v_slices,
    'teacher_decisions_recorded',v_recorded,
    'teacher_approved',v_approved,
    'teacher_changes_required',v_changes,
    'unreviewed_estimate',greatest(v_active-v_recorded,0),
    'coverage_gap_estimate',greatest(v_active-v_in_slices,0),
    'generated_at',now(),
    'warning','Recorded teacher decisions require qualifications and historical subject-authority audit; this is not a certification of all active questions.'
  );
end $fn$;
revoke all on function public.get_my_question_review_progress_v39(text) from public,anon;
grant execute on function public.get_my_question_review_progress_v39(text) to authenticated,service_role;

-- Existing review submission API stays intact for backward compatibility;
-- its private implementation invokes question_reviewer_allowed_v18 before writes.

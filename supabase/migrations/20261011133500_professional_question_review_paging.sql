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

  select count(distinct q.id) into v_in_slices
  from private.mela_question_review_slices_v18 s
  cross join lateral unnest(s.question_ids) ids(question_id)
  join public.mela_question_bank q on q.id=ids.question_id and q.active
  where (p_program_key is null or s.program_key=p_program_key)
    and private.question_reviewer_allowed_v18(v_uid,s.program_key);

  select count(*) into v_slices from private.mela_question_review_slices_v18 s
  where (p_program_key is null or s.program_key=p_program_key)
    and private.question_reviewer_allowed_v18(v_uid,s.program_key);

  select count(distinct d.question_id),
    count(distinct d.question_id) filter(where d.decision='approved'),
    count(distinct d.question_id) filter(where d.decision='changes_required')
  into v_recorded,v_approved,v_changes
  from private.mela_question_review_decisions_v18 d
  join private.mela_question_review_slices_v18 s on s.id=d.slice_id
  join public.mela_question_bank q on q.id=d.question_id and q.active
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

-- Claim ownership before editing, eliminating simultaneous teachers overwriting one another.
create or replace function public.claim_question_review_slice_v39(p_slice_id bigint)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare v_uid uuid:=(select auth.uid()); v_slice private.mela_question_review_slices_v18%rowtype;
begin
  if v_uid is null then raise exception 'sign in required' using errcode='42501'; end if;
  select * into v_slice from private.mela_question_review_slices_v18
  where id=p_slice_id for update;
  if not found then raise exception 'review slice not found'; end if;
  if not private.question_reviewer_allowed_v18(v_uid,v_slice.program_key)
    then raise exception 'verified teacher subject and grade access required' using errcode='42501'; end if;
  if v_slice.assigned_to is not null and v_slice.assigned_to<>v_uid
    then raise exception 'another teacher already owns this review slice' using errcode='42501'; end if;
  if v_slice.status='approved' then raise exception 'this review slice is already approved'; end if;
  update private.mela_question_review_slices_v18
    set assigned_to=v_uid,status=case when status='pending' then 'assigned' else status end,
        updated_at=now()
    where id=p_slice_id;
  return jsonb_build_object('slice_id',p_slice_id,'assigned_to_me',true);
end $fn$;
revoke all on function public.claim_question_review_slice_v39(bigint) from public,anon;
grant execute on function public.claim_question_review_slice_v39(bigint) to authenticated,service_role;

-- Keep the existing public function signature so older clients continue to
-- work once they claim the slice. The database, not a UI checkbox, enforces
-- actual teacher identity and a nonempty human verification note.
create or replace function public.review_question_slice_v18(p_slice_id bigint,p_decisions jsonb)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare v_uid uuid:=(select auth.uid()); v_slice private.mela_question_review_slices_v18%rowtype; v_entry jsonb;
begin
  if v_uid is null or jsonb_typeof(p_decisions)<>'array' or jsonb_array_length(p_decisions) < 1
    then raise exception 'one or more authenticated review decisions are required'; end if;
  select * into v_slice from private.mela_question_review_slices_v18
    where id=p_slice_id for update;
  if not found then raise exception 'review slice not found'; end if;
  if not private.question_reviewer_allowed_v18(v_uid,v_slice.program_key)
    then raise exception 'verified teacher subject and grade access required' using errcode='42501'; end if;
  if v_slice.assigned_to is distinct from v_uid
    then raise exception 'claim your review slice before recording decisions' using errcode='42501'; end if;
  if v_slice.status='approved' then raise exception 'already approved; request an authorized re-review'; end if;
  for v_entry in select value from jsonb_array_elements(p_decisions) loop
    if char_length(btrim(coalesce(v_entry->>'note',''))) < 5
      then raise exception 'each review decision requires a teacher note of at least five characters'; end if;
    if v_entry->>'decision'='approved' and not (
       v_entry->>'note' like 'Teacher test response:%' and
       v_entry->>'note' like E'%\nVerification:%'
    ) then raise exception 'approval requires recorded human test response and verification evidence'; end if;
  end loop;
  return private.review_question_slice_v18(p_slice_id,p_decisions);
end $fn$;
revoke all on function public.review_question_slice_v18(bigint,jsonb) from public,anon;
grant execute on function public.review_question_slice_v18(bigint,jsonb) to authenticated,service_role;

-- Grading evidence may only be loaded for slices claimed by the teacher.
create or replace function public.get_question_review_slice_v18(p_slice_id bigint)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_uid uuid:=(select auth.uid()); v_slice private.mela_question_review_slices_v18%rowtype;
begin
  if v_uid is null then raise exception 'verified teacher sign-in required' using errcode='42501'; end if;
  select * into v_slice from private.mela_question_review_slices_v18 where id=p_slice_id;
  if not found then raise exception 'review slice not found'; end if;
  if not private.question_reviewer_allowed_v18(v_uid,v_slice.program_key)
    or v_slice.assigned_to is distinct from v_uid
    then raise exception 'claim your subject-qualified review slice before opening grading evidence' using errcode='42501'; end if;
  return private.get_question_review_slice_v18(p_slice_id);
end $fn$;
revoke all on function public.get_question_review_slice_v18(bigint) from public,anon;
grant execute on function public.get_question_review_slice_v18(bigint) to authenticated,service_role;

-- Prevent authenticated callers from invoking the legacy privileged
-- implementations directly. Public SECURITY DEFINER wrappers remain the only
-- browser-authorized entry points for grading and decision writes.
revoke all on function private.get_question_review_slice_v18(bigint) from public,anon,authenticated;
revoke all on function private.review_question_slice_v18(bigint,jsonb) from public,anon,authenticated;
grant execute on function private.get_question_review_slice_v18(bigint) to service_role;
grant execute on function private.review_question_slice_v18(bigint,jsonb) to service_role;

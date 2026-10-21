-- Run against isolated, migrated MELA staging only.
-- Does not mutate live student or review data.
begin;
do $checks$
declare v_definition text;
begin
  if has_function_privilege('anon','public.get_question_review_queue_page_v39(text,text,integer,integer)','EXECUTE')
    or has_function_privilege('anon','public.get_my_question_review_progress_v39(text)','EXECUTE')
    or has_function_privilege('anon','public.claim_question_review_slice_v39(bigint)','EXECUTE')
    or has_function_privilege('anon','public.get_question_review_slice_v18(bigint)','EXECUTE')
    or has_function_privilege('anon','public.review_question_slice_v18(bigint,jsonb)','EXECUTE')
  then raise exception 'anonymous users can access teacher review actions'; end if;
  if not has_function_privilege('authenticated','public.get_question_review_queue_page_v39(text,text,integer,integer)','EXECUTE')
    or not has_function_privilege('authenticated','public.claim_question_review_slice_v39(bigint)','EXECUTE')
  then raise exception 'qualified teacher endpoints are not callable by authenticated role'; end if;
  v_definition := pg_get_functiondef('private.question_reviewer_allowed_v18(uuid,text)'::regprocedure);
  if position('private.is_admin_user' in v_definition)>0
    then raise exception 'admin bypass still present in professional reviewer authorization'; end if;
  if position('t.verification_status' in v_definition)=0
    then raise exception 'professional teacher verification gate missing'; end if;
  if position('t.grade_levels' in v_definition)=0
    then raise exception 'review grade scope missing'; end if;
  v_definition := pg_get_functiondef('public.review_question_slice_v18(bigint,jsonb)'::regprocedure);
  if position('assigned_to' in v_definition)=0
    then raise exception 'submission does not enforce claimed reviewer'; end if;
  if position('Teacher test response:' in v_definition)=0
    then raise exception 'human-answer evidence gate missing'; end if;
end;
$checks$;
rollback;

-- Additional live staging tests (must be done by human QA on disposable data):
-- 1. anonymous -> every review RPC returns 401/42501.
-- 2. admin-only profile -> can verify teachers, cannot inspect grading keys, claim or approve.
-- 3. unverified teacher -> no review content or claims.
-- 4. verified math teacher Grade 4 -> claim/read Math Grade 4; cannot claim Grade 8 or Science.
-- 5. another verified teacher -> cannot submit or view the first teacher's claimed grading keys.
-- 6. owner teacher -> rejects empty decisions, missing self-test evidence and invalid notes.
-- 7. owner teacher -> saved decision stamped with actual reviewer_id and only then updates bank validation status.
-- 8. stage reconciliation has no missing active question UUID and no duplicate IDs in slices.

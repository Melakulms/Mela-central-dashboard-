-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826134633
CREATE OR REPLACE FUNCTION public.admin_review_employer_registration(p_request_id uuid, p_status text, p_review_notes text)
RETURNS public.employer_registration_requests
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare r public.employer_registration_requests;
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;
  if p_status not in ('approved','rejected','pending','review') then raise exception 'invalid employer status'; end if;
  if p_status in ('approved','rejected') and nullif(trim(p_review_notes),'') is null then raise exception 'review reason is required'; end if;
  update public.employer_registration_requests set status=p_status,review_notes=nullif(trim(p_review_notes),''),reviewed_at=now()
  where id=p_request_id and status in ('pending','review','review_required')
  and ((status='pending' and p_status in ('pending','review','approved','rejected')) or (status='review' and p_status in ('pending','review','approved','rejected')) or (status='review_required' and p_status in ('review','approved','rejected')))
  returning * into r;
  if not found then raise exception 'invalid transition or concurrent modification'; end if;
  return r;
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_assessment_answer_key(p_question_id uuid,p_correct_answer jsonb,p_explanation text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','private','public'
AS $function$
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;
  if not exists(select 1 from public.assessment_questions where id=p_question_id) then raise exception 'Assessment question not found'; end if;
  insert into private.assessment_answer_keys(question_id,correct_answer,explanation,updated_at) values(p_question_id,p_correct_answer,p_explanation,now())
  on conflict(question_id) do update set correct_answer=excluded.correct_answer,explanation=excluded.explanation,updated_at=now();
  return jsonb_build_object('question_id',p_question_id,'saved',true);
end;
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_practice_answer_key(p_question_id uuid,p_correct_answer jsonb,p_rubric jsonb DEFAULT '{}'::jsonb,p_explanation text DEFAULT NULL::text,p_auto_gradable boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','private','public'
AS $function$
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;
  if not exists(select 1 from public.practice_questions where id=p_question_id) then raise exception 'Practice question not found'; end if;
  insert into private.practice_answer_keys(question_id,correct_answer,rubric,explanation,auto_gradable,created_at,updated_at) values(p_question_id,p_correct_answer,coalesce(p_rubric,'{}'::jsonb),p_explanation,p_auto_gradable,now(),now())
  on conflict(question_id) do update set correct_answer=excluded.correct_answer,rubric=excluded.rubric,explanation=excluded.explanation,auto_gradable=excluded.auto_gradable,updated_at=now();
  return jsonb_build_object('question_id',p_question_id,'saved',true);
end;
$function$;
;

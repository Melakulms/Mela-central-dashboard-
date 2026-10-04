-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815171318
alter function public.get_question_review_queue_v18(text,integer) set schema private;
alter function public.get_question_review_slice_v18(bigint) set schema private;
alter function public.review_question_slice_v18(bigint,jsonb) set schema private;
alter function public.get_generated_question_candidates_v18(text,integer) set schema private;
alter function public.review_generated_question_candidate_v18(uuid,text,text) set schema private;
alter function public.promote_generated_question_candidate_v18(uuid) set schema private;

grant execute on function private.get_question_review_queue_v18(text,integer) to authenticated;
grant execute on function private.get_question_review_slice_v18(bigint) to authenticated;
grant execute on function private.review_question_slice_v18(bigint,jsonb) to authenticated;
grant execute on function private.get_generated_question_candidates_v18(text,integer) to authenticated;
grant execute on function private.review_generated_question_candidate_v18(uuid,text,text) to authenticated;
grant execute on function private.promote_generated_question_candidate_v18(uuid) to authenticated;

create function public.get_question_review_queue_v18(p_program_key text default null,p_limit integer default 50) returns jsonb language sql stable security invoker set search_path='' as $$ select private.get_question_review_queue_v18(p_program_key,p_limit); $$;
create function public.get_question_review_slice_v18(p_slice_id bigint) returns jsonb language sql stable security invoker set search_path='' as $$ select private.get_question_review_slice_v18(p_slice_id); $$;
create function public.review_question_slice_v18(p_slice_id bigint,p_decisions jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.review_question_slice_v18(p_slice_id,p_decisions); $$;
create function public.get_generated_question_candidates_v18(p_program_key text default null,p_limit integer default 50) returns jsonb language sql stable security invoker set search_path='' as $$ select private.get_generated_question_candidates_v18(p_program_key,p_limit); $$;
create function public.review_generated_question_candidate_v18(p_candidate_id uuid,p_decision text,p_note text default null) returns jsonb language sql security invoker set search_path='' as $$ select private.review_generated_question_candidate_v18(p_candidate_id,p_decision,p_note); $$;
create function public.promote_generated_question_candidate_v18(p_candidate_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.promote_generated_question_candidate_v18(p_candidate_id); $$;

revoke all on function public.get_question_review_queue_v18(text,integer) from public,anon;
revoke all on function public.get_question_review_slice_v18(bigint) from public,anon;
revoke all on function public.review_question_slice_v18(bigint,jsonb) from public,anon;
revoke all on function public.get_generated_question_candidates_v18(text,integer) from public,anon;
revoke all on function public.review_generated_question_candidate_v18(uuid,text,text) from public,anon;
revoke all on function public.promote_generated_question_candidate_v18(uuid) from public,anon;
grant execute on function public.get_question_review_queue_v18(text,integer) to authenticated;
grant execute on function public.get_question_review_slice_v18(bigint) to authenticated;
grant execute on function public.review_question_slice_v18(bigint,jsonb) to authenticated;
grant execute on function public.get_generated_question_candidates_v18(text,integer) to authenticated;
grant execute on function public.review_generated_question_candidate_v18(uuid,text,text) to authenticated;
grant execute on function public.promote_generated_question_candidate_v18(uuid) to authenticated;
;

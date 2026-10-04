-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815165526
create or replace function public.start_mela_filtered_question_session_v15(p_program_key text,p_chapter_id uuid default null,p_topic_id uuid default null,p_count integer default 10,p_difficulty integer default null) returns jsonb language sql set search_path='' as $$ select private.start_mela_filtered_question_session_v18(p_program_key,p_chapter_id,p_topic_id,p_count,p_difficulty,'mastery'); $$;
create or replace function public.start_mela_question_session_v12(p_program_key text,p_count integer default 20,p_difficulty integer default null) returns jsonb language sql set search_path='' as $$ select private.start_mela_filtered_question_session_v18(p_program_key,null,null,p_count,p_difficulty,'mastery'); $$;
revoke all on function public.start_mela_filtered_question_session_v15(text,uuid,uuid,integer,integer) from public,anon;
grant execute on function public.start_mela_filtered_question_session_v15(text,uuid,uuid,integer,integer) to authenticated;
revoke all on function public.start_mela_question_session_v12(text,integer,integer) from public,anon;
grant execute on function public.start_mela_question_session_v12(text,integer,integer) to authenticated;
;

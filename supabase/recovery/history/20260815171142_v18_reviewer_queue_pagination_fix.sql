-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815171142
create or replace function public.get_question_review_queue_v18(p_program_key text default null,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_limit int:=least(greatest(coalesce(p_limit,50),1),100); begin
 if v_uid is null then raise exception 'authentication required'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('slice_id',z.id,'program_key',z.program_key,'grade_level',z.grade_level,'subject_title',z.subject_title,'track_key',z.track_key,'slice_number',z.slice_number,'question_count',z.question_count,'status',z.status,'assigned_to',z.assigned_to,'reviewed_at',z.reviewed_at) order by z.grade_level,z.subject_title,z.slice_number)
 from (
   select s.id,s.program_key,p.grade_level,p.subject_title,p.track_key,s.slice_number,s.question_count,s.status,s.assigned_to,s.reviewed_at
   from private.mela_question_review_slices_v18 s join public.mela_learning_programs p on p.program_key=s.program_key
   where (p_program_key is null or s.program_key=p_program_key) and private.question_reviewer_allowed_v18(v_uid,s.program_key)
   order by p.grade_level,p.subject_title,s.slice_number limit v_limit
 ) z),'[]'::jsonb);
end $$;
revoke all on function public.get_question_review_queue_v18(text,integer) from public,anon;
grant execute on function public.get_question_review_queue_v18(text,integer) to authenticated;

create or replace function public.get_generated_question_candidates_v18(p_program_key text default null,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_limit int:=least(greatest(coalesce(p_limit,50),1),100); begin
 if v_uid is null then raise exception 'authentication required'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('candidate_id',z.id,'target_question_id',z.target_question_id,'program_key',z.program_key,'grade_level',z.grade_level,'subject_title',z.subject_title,'chapter_title',z.chapter_title,'topic_title',z.topic_title,'question_type',z.proposed_question_type,'prompt',z.prompt,'choices',z.choices,'difficulty',z.difficulty,'cognitive_level',z.cognitive_level,'access_tier',z.access_tier,'grading_kind',z.grading_kind,'correct_response',z.correct_response,'accepted_variants',z.accepted_variants,'tolerance',z.tolerance,'rationale',z.rationale,'machine_quality_score',z.machine_quality_score,'quality_checks',z.quality_checks,'status',z.status,'generation_model',z.generation_model,'reviewer_note',z.reviewer_note) order by z.grade_level,z.subject_title,z.generated_at)
 from (
   select c.id,c.target_question_id,c.program_key,p.grade_level,p.subject_title,ch.title chapter_title,tp.title topic_title,c.proposed_question_type,c.prompt,c.choices,c.difficulty,c.cognitive_level,t.access_tier,c.grading_kind,c.correct_response,c.accepted_variants,c.tolerance,c.rationale,c.machine_quality_score,c.quality_checks,c.status,c.generation_model,c.reviewer_note,c.generated_at
   from private.mela_question_generation_candidates_v18 c
   join private.mela_question_replacement_targets_v18 t on t.target_question_id=c.target_question_id
   join public.mela_learning_programs p on p.program_key=c.program_key
   left join public.mela_learning_chapters ch on ch.id=c.chapter_id left join public.mela_learning_chapter_topics tp on tp.id=c.topic_id
   where (p_program_key is null or c.program_key=p_program_key) and c.status in ('generated','machine_validated','changes_required','educator_approved') and private.question_reviewer_allowed_v18(v_uid,c.program_key)
   order by p.grade_level,p.subject_title,c.generated_at limit v_limit
 ) z),'[]'::jsonb);
end $$;
revoke all on function public.get_generated_question_candidates_v18(text,integer) from public,anon;
grant execute on function public.get_generated_question_candidates_v18(text,integer) to authenticated;
;

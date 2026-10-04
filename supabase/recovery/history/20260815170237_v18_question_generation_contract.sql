-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815170237
create or replace function public.get_question_generation_batch_v18(p_limit integer default 5,p_program_key text default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_limit integer:=least(greatest(coalesce(p_limit,5),1),10); v_ids uuid[]:='{}'; begin
  select coalesce(array_agg(target_question_id),'{}'::uuid[]) into v_ids
  from (
    select t.target_question_id from private.mela_question_replacement_targets_v18 t
    where t.status='queued' and (p_program_key is null or t.program_key=p_program_key)
    order by t.priority,t.grade_level,t.subject_title,t.target_question_id
    for update skip locked limit v_limit
  ) s;
  if cardinality(v_ids)=0 then return '[]'::jsonb; end if;
  update private.mela_question_replacement_targets_v18 set status='generating',updated_at=now() where target_question_id=any(v_ids);
  return coalesce((select jsonb_agg(jsonb_build_object(
    'target_question_id',t.target_question_id,'program_key',t.program_key,'grade_level',t.grade_level,'subject_title',t.subject_title,'subject_key',p.subject_key,'track_key',p.track_key,
    'chapter_id',t.chapter_id,'chapter_title',c.title,'chapter_description',c.description,'chapter_learning_outcomes',c.learning_outcomes,'chapter_source_kind',c.source_kind,'chapter_source_verified',c.source_verified,'chapter_alignment_status',c.official_alignment_status,
    'topic_id',t.topic_id,'topic_title',tp.title,'desired_question_type',t.desired_question_type,'access_tier',t.access_tier,'target_reason',t.target_reason,
    'old_prompt',q.prompt,'old_question_type',q.question_type,'difficulty',q.difficulty,'cognitive_level',q.cognitive_level,
    'source_context',coalesce(ctx.content,'')) order by t.priority,t.target_question_id)
    from private.mela_question_replacement_targets_v18 t
    join public.mela_learning_programs p on p.program_key=t.program_key
    join public.mela_question_bank q on q.id=t.target_question_id
    left join public.mela_learning_chapters c on c.id=t.chapter_id
    left join public.mela_learning_chapter_topics tp on tp.id=t.topic_id
    left join lateral (
      select string_agg(left(z.content_markdown,2500),E'\n\n---\n\n') content from (
        select mc.content_markdown
        from public.mela_learning_chapter_materials m join public.mela_learning_chapter_material_content mc on mc.material_id=m.id
        where m.chapter_id=t.chapter_id and m.status='published' and m.material_type in ('lesson','summary','worked_examples','guided_practice')
        order by case m.material_type when 'lesson' then 1 when 'summary' then 2 when 'worked_examples' then 3 else 4 end
        limit 3
      ) z
    ) ctx on true
    where t.target_question_id=any(v_ids)),'[]'::jsonb);
end $$;
revoke all on function public.get_question_generation_batch_v18(integer,text) from public,anon,authenticated;
grant execute on function public.get_question_generation_batch_v18(integer,text) to service_role;

create or replace function public.store_question_generation_candidate_v18(p_target_question_id uuid,p_candidate jsonb,p_model text,p_batch_id uuid default null)
returns uuid language plpgsql security definer set search_path=''
as $$
declare t private.mela_question_replacement_targets_v18%rowtype; v_id uuid; v_type text; v_prompt text; v_diff int; v_cog text; v_score numeric:=70; begin
  select * into t from private.mela_question_replacement_targets_v18 where target_question_id=p_target_question_id for update;
  if not found then raise exception 'replacement target not found'; end if;
  if t.status not in ('generating','changes_required') then raise exception 'target is not accepting a generated candidate'; end if;
  v_type:=p_candidate->>'question_type'; v_prompt:=btrim(coalesce(p_candidate->>'prompt','')); v_diff:=coalesce((p_candidate->>'difficulty')::int,0); v_cog:=p_candidate->>'cognitive_level';
  if v_type is distinct from t.desired_question_type then raise exception 'candidate question type does not match target type'; end if;
  if length(v_prompt)<20 or length(v_prompt)>1200 then raise exception 'candidate prompt length invalid'; end if;
  if v_prompt ~* '(which chapter|mapped topic|how to study|study item|chapter has [0-9]+ mapped learning topics|chapter should the learner open)' then raise exception 'candidate contains curriculum-navigation/meta-study pattern'; end if;
  if v_diff<1 or v_diff>5 then raise exception 'candidate difficulty invalid'; end if;
  if v_cog not in ('remember','understand','apply','analyze') then raise exception 'candidate cognitive level invalid'; end if;
  if jsonb_typeof(coalesce(p_candidate->'choices','[]'::jsonb))<>'array' then raise exception 'candidate choices must be an array'; end if;
  if nullif(btrim(coalesce(p_candidate->>'grading_kind','')),'') is null or p_candidate->'correct_response' is null then raise exception 'candidate grading data required'; end if;
  if length(btrim(coalesce(p_candidate->>'rationale','')))<20 then raise exception 'candidate rationale too short'; end if;
  if length(v_prompt)>=40 then v_score:=v_score+5; end if;
  if v_cog in ('apply','analyze') then v_score:=v_score+5; end if;
  if v_type in ('scenario_choice','passage_choice','multi_select','numeric','short_answer','matching','ordering') then v_score:=v_score+5; end if;
  insert into private.mela_question_generation_candidates_v18(target_question_id,program_key,chapter_id,topic_id,proposed_question_type,prompt,choices,difficulty,cognitive_level,narration_text,response_schema,estimated_seconds,accessibility_support,grading_kind,correct_response,accepted_variants,tolerance,rationale,generation_model,generation_batch_id,machine_quality_score,quality_checks,status)
  values(t.target_question_id,t.program_key,t.chapter_id,t.topic_id,v_type,v_prompt,coalesce(p_candidate->'choices','[]'::jsonb),v_diff,v_cog,nullif(p_candidate->>'narration_text',''),coalesce(p_candidate->'response_schema','{}'::jsonb),coalesce((p_candidate->>'estimated_seconds')::int,90),coalesce(p_candidate->'accessibility_support','{}'::jsonb),p_candidate->>'grading_kind',p_candidate->'correct_response',coalesce(p_candidate->'accepted_variants','[]'::jsonb),nullif(p_candidate->>'tolerance','')::numeric,btrim(p_candidate->>'rationale'),p_model,p_batch_id,v_score,jsonb_build_object('v18_structural_validation',true,'anti_meta_pattern',true,'desired_type_match',true),'generated')
  on conflict(target_question_id) do update set proposed_question_type=excluded.proposed_question_type,prompt=excluded.prompt,choices=excluded.choices,difficulty=excluded.difficulty,cognitive_level=excluded.cognitive_level,narration_text=excluded.narration_text,response_schema=excluded.response_schema,estimated_seconds=excluded.estimated_seconds,accessibility_support=excluded.accessibility_support,grading_kind=excluded.grading_kind,correct_response=excluded.correct_response,accepted_variants=excluded.accepted_variants,tolerance=excluded.tolerance,rationale=excluded.rationale,generation_model=excluded.generation_model,generation_batch_id=excluded.generation_batch_id,machine_quality_score=excluded.machine_quality_score,quality_checks=excluded.quality_checks,status='generated',updated_at=now()
  returning id into v_id;
  update private.mela_question_replacement_targets_v18 set status='generated',updated_at=now() where target_question_id=t.target_question_id;
  return v_id;
end $$;
revoke all on function public.store_question_generation_candidate_v18(uuid,jsonb,text,uuid) from public,anon,authenticated;
grant execute on function public.store_question_generation_candidate_v18(uuid,jsonb,text,uuid) to service_role;

create or replace function public.reset_stale_question_generation_claims_v18()
returns integer language plpgsql security definer set search_path=''
as $$ declare v_n integer; begin
 update private.mela_question_replacement_targets_v18 t set status='queued',updated_at=now()
 where t.status='generating' and t.updated_at<now()-interval '30 minutes' and not exists(select 1 from private.mela_question_generation_candidates_v18 c where c.target_question_id=t.target_question_id);
 get diagnostics v_n=row_count; return v_n; end $$;
revoke all on function public.reset_stale_question_generation_claims_v18() from public,anon,authenticated;
grant execute on function public.reset_stale_question_generation_claims_v18() to service_role;
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815170702
create or replace function private.reconcile_program_replacement_targets_v18(p_program_key text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_mastery int; v_needed int; v_open int; v_add int; v_added int:=0; v_subject text; v_grade smallint; begin
 select count(*)::int into v_mastery from public.mela_question_bank where program_key=p_program_key and active and validation_status in ('deterministic_validated','educator_verified');
 v_needed:=greatest(500-v_mastery,0);
 select count(*)::int into v_open from private.mela_question_replacement_targets_v18 where program_key=p_program_key and status in ('queued','generating','generated','machine_validated','educator_approved','changes_required');
 v_add:=greatest(v_needed-v_open,0);
 if v_add>0 then
   select grade_level,subject_title into v_grade,v_subject from public.mela_learning_programs where program_key=p_program_key;
   with c as (
     select q.id,q.chapter_id,q.topic_id,q.question_type,q.access_tier,q.question_number,row_number() over(order by q.question_number) rn
     from public.mela_question_bank q
     where q.program_key=p_program_key and q.active and q.validation_status='review_required'
       and not exists(select 1 from private.mela_question_replacement_targets_v18 t where t.target_question_id=q.id)
     order by q.question_number limit v_add
   )
   insert into private.mela_question_replacement_targets_v18(target_question_id,program_key,chapter_id,topic_id,grade_level,subject_title,current_question_type,desired_question_type,access_tier,priority,target_reason)
   select id,p_program_key,chapter_id,topic_id,v_grade,v_subject,question_type,question_type,access_tier,500+rn,'educator review increased program mastery gap' from c;
   get diagnostics v_added=row_count;
 end if;
 update private.mela_question_regeneration_queue_v18 set current_mastery_count=v_mastery,questions_needed=v_needed,status=case when v_needed=0 then 'complete' when status='complete' then 'queued' else status end,updated_at=now() where program_key=p_program_key;
 return jsonb_build_object('program_key',p_program_key,'mastery_count',v_mastery,'questions_needed',v_needed,'open_targets_before',v_open,'targets_added',v_added);
end $$;
revoke all on function private.reconcile_program_replacement_targets_v18(text) from public,anon,authenticated;
grant execute on function private.reconcile_program_replacement_targets_v18(text) to service_role;

create or replace function public.get_generated_question_candidates_v18(p_program_key text default null,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_limit int:=least(greatest(coalesce(p_limit,50),1),100); begin
 if v_uid is null then raise exception 'authentication required'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('candidate_id',c.id,'target_question_id',c.target_question_id,'program_key',c.program_key,'grade_level',p.grade_level,'subject_title',p.subject_title,'chapter_title',ch.title,'topic_title',tp.title,'question_type',c.proposed_question_type,'prompt',c.prompt,'choices',c.choices,'difficulty',c.difficulty,'cognitive_level',c.cognitive_level,'access_tier',t.access_tier,'grading_kind',c.grading_kind,'correct_response',c.correct_response,'accepted_variants',c.accepted_variants,'tolerance',c.tolerance,'rationale',c.rationale,'machine_quality_score',c.machine_quality_score,'quality_checks',c.quality_checks,'status',c.status,'generation_model',c.generation_model,'reviewer_note',c.reviewer_note) order by p.grade_level,p.subject_title,c.generated_at)
 from private.mela_question_generation_candidates_v18 c
 join private.mela_question_replacement_targets_v18 t on t.target_question_id=c.target_question_id
 join public.mela_learning_programs p on p.program_key=c.program_key
 left join public.mela_learning_chapters ch on ch.id=c.chapter_id left join public.mela_learning_chapter_topics tp on tp.id=c.topic_id
 where (p_program_key is null or c.program_key=p_program_key) and c.status in ('generated','machine_validated','changes_required','educator_approved') and private.question_reviewer_allowed_v18(v_uid,c.program_key)
 limit v_limit),'[]'::jsonb);
end $$;
revoke all on function public.get_generated_question_candidates_v18(text,integer) from public,anon;
grant execute on function public.get_generated_question_candidates_v18(text,integer) to authenticated;

create or replace function public.review_generated_question_candidate_v18(p_candidate_id uuid,p_decision text,p_note text default null)
returns jsonb language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); c private.mela_question_generation_candidates_v18%rowtype; v_status text; begin
 if v_uid is null then raise exception 'authentication required'; end if;
 if p_decision not in ('approved','changes_required','rejected') then raise exception 'invalid decision'; end if;
 select * into c from private.mela_question_generation_candidates_v18 where id=p_candidate_id for update;
 if not found then raise exception 'candidate not found'; end if;
 if not private.question_reviewer_allowed_v18(v_uid,c.program_key) then raise exception 'verified educator subject access required'; end if;
 v_status:=case p_decision when 'approved' then 'educator_approved' when 'changes_required' then 'changes_required' else 'rejected' end;
 update private.mela_question_generation_candidates_v18 set status=v_status,reviewed_by=v_uid,reviewed_at=now(),reviewer_note=nullif(btrim(coalesce(p_note,'')),''),updated_at=now() where id=p_candidate_id;
 update private.mela_question_replacement_targets_v18 set status=case p_decision when 'approved' then 'educator_approved' when 'changes_required' then 'changes_required' else 'rejected' end,updated_at=now() where target_question_id=c.target_question_id;
 if p_decision='rejected' then perform private.reconcile_program_replacement_targets_v18(c.program_key); end if;
 return jsonb_build_object('candidate_id',p_candidate_id,'status',v_status,'program_key',c.program_key);
end $$;
revoke all on function public.review_generated_question_candidate_v18(uuid,text,text) from public,anon;
grant execute on function public.review_generated_question_candidate_v18(uuid,text,text) to authenticated;

create or replace function public.promote_generated_question_candidate_v18(p_candidate_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); c private.mela_question_generation_candidates_v18%rowtype; t private.mela_question_replacement_targets_v18%rowtype; v_role text; v_state jsonb; begin
 if v_uid is null then raise exception 'authentication required'; end if;
 select role into v_role from public.profiles where id=v_uid;
 if v_role is distinct from 'admin' then raise exception 'admin role required for promotion'; end if;
 select * into c from private.mela_question_generation_candidates_v18 where id=p_candidate_id for update;
 if not found or c.status<>'educator_approved' then raise exception 'educator-approved candidate required'; end if;
 select * into t from private.mela_question_replacement_targets_v18 where target_question_id=c.target_question_id for update;
 if not found or t.status<>'educator_approved' then raise exception 'approved replacement target required'; end if;
 update public.mela_question_bank q set question_type=c.proposed_question_type,prompt=c.prompt,choices=c.choices,difficulty=c.difficulty,cognitive_level=c.cognitive_level,narration_text=coalesce(c.narration_text,c.prompt),response_schema=c.response_schema,estimated_seconds=c.estimated_seconds,accessibility_support=c.accessibility_support,machine_quality_score=greatest(c.machine_quality_score,85),validation_status='educator_verified',source_status='mela_supplemental',generation_version='v18',quality_checks=coalesce(q.quality_checks,'{}'::jsonb)||c.quality_checks||jsonb_build_object('v18_replacement_promoted',true,'v18_replacement_candidate_id',c.id,'v18_promoted_at',now(),'v18_promoted_by',v_uid),updated_at=now() where q.id=c.target_question_id;
 update private.mela_question_grading_v12 set grading_kind=c.grading_kind,correct_response=c.correct_response,accepted_variants=c.accepted_variants,tolerance=c.tolerance,rationale=c.rationale,grading_version='v18',updated_at=now() where question_id=c.target_question_id;
 update private.mela_question_quality_audit_v18 set purpose_class='subject_mastery_candidate',requires_regeneration=false,audit_flags=audit_flags||jsonb_build_object('v18_replacement_promoted',true,'candidate_id',c.id,'promoted_at',now()),audited_at=now() where question_id=c.target_question_id;
 update private.mela_question_generation_candidates_v18 set status='promoted',promoted_at=now(),updated_at=now() where id=c.id;
 update private.mela_question_replacement_targets_v18 set status='promoted',updated_at=now() where target_question_id=c.target_question_id;
 v_state:=private.reconcile_program_replacement_targets_v18(c.program_key);
 update public.mela_question_review_batches b set educator_verified_count=(select count(*) from public.mela_question_bank q where q.program_key=c.program_key and q.active and q.validation_status='educator_verified'),deterministic_validated_count=(select count(*) from public.mela_question_bank q where q.program_key=c.program_key and q.active and q.validation_status in ('deterministic_validated','educator_verified')),review_status=case when (v_state->>'questions_needed')::int=0 and not exists(select 1 from public.mela_question_bank q where q.program_key=c.program_key and q.active and q.validation_status='review_required') then 'in_review' else 'changes_required' end,updated_at=now() where b.program_key=c.program_key;
 return jsonb_build_object('candidate_id',c.id,'target_question_id',c.target_question_id,'program_key',c.program_key,'promoted',true,'rebuild_state',v_state);
end $$;
revoke all on function public.promote_generated_question_candidate_v18(uuid) from public,anon;
grant execute on function public.promote_generated_question_candidate_v18(uuid) to authenticated;
;

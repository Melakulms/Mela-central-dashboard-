-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815170741
create or replace function public.review_question_slice_v18(p_slice_id bigint,p_decisions jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); s private.mela_question_review_slices_v18%rowtype; x jsonb; v_q uuid; v_dec text; v_total int; v_done int; v_approved int; v_changes int; v_rebuild jsonb; begin
 if v_uid is null then raise exception 'authentication required'; end if;
 if jsonb_typeof(p_decisions)<>'array' then raise exception 'decisions must be an array'; end if;
 select * into s from private.mela_question_review_slices_v18 where id=p_slice_id for update;
 if not found then raise exception 'review slice not found'; end if;
 if not private.question_reviewer_allowed_v18(v_uid,s.program_key) then raise exception 'verified educator subject access required'; end if;
 foreach x in array(select array_agg(value) from jsonb_array_elements(p_decisions)) loop
   v_q:=(x->>'question_id')::uuid; v_dec:=x->>'decision';
   if not (v_q=any(s.question_ids)) then raise exception 'question does not belong to this review slice'; end if;
   if v_dec not in ('approved','changes_required') then raise exception 'invalid review decision'; end if;
   insert into private.mela_question_review_decisions_v18(slice_id,question_id,reviewer_id,decision,note,reviewed_at)
   values(s.id,v_q,v_uid,v_dec,nullif(btrim(coalesce(x->>'note','')),''),now())
   on conflict(slice_id,question_id) do update set reviewer_id=excluded.reviewer_id,decision=excluded.decision,note=excluded.note,reviewed_at=excluded.reviewed_at;
   if v_dec='approved' then
     update public.mela_question_bank set validation_status='educator_verified',quality_checks=quality_checks||jsonb_build_object('v18_educator_verified',true,'v18_educator_verified_at',now()),updated_at=now() where id=v_q;
   else
     update public.mela_question_bank set validation_status='review_required',machine_quality_score=least(machine_quality_score,60),quality_checks=quality_checks||jsonb_build_object('v18_educator_changes_required',true,'v18_educator_reviewed_at',now()),updated_at=now() where id=v_q;
   end if;
 end loop;
 select count(*) into v_total from unnest(s.question_ids);
 select count(*),count(*) filter(where decision='approved'),count(*) filter(where decision='changes_required') into v_done,v_approved,v_changes from private.mela_question_review_decisions_v18 where slice_id=s.id;
 update private.mela_question_review_slices_v18 set status=case when v_done=v_total and v_changes=0 then 'approved' when v_done=v_total and v_changes>0 then 'changes_required' when v_done>0 then 'in_review' else 'pending' end,reviewed_at=case when v_done=v_total then now() else reviewed_at end,updated_at=now() where id=s.id;
 v_rebuild:=private.reconcile_program_replacement_targets_v18(s.program_key);
 update public.mela_question_review_batches b set educator_verified_count=(select count(*) from public.mela_question_bank q where q.program_key=s.program_key and q.active and q.validation_status='educator_verified'),deterministic_validated_count=(select count(*) from public.mela_question_bank q where q.program_key=s.program_key and q.active and q.validation_status in ('deterministic_validated','educator_verified')),review_status=case when (v_rebuild->>'questions_needed')::int>0 or exists(select 1 from public.mela_question_bank q where q.program_key=s.program_key and q.active and q.validation_status='review_required') then 'changes_required' else 'in_review' end,updated_at=now() where b.program_key=s.program_key;
 return jsonb_build_object('slice_id',s.id,'reviewed',v_done,'approved',v_approved,'changes_required',v_changes,'total',v_total,'rebuild_state',v_rebuild);
end $$;
revoke all on function public.review_question_slice_v18(bigint,jsonb) from public,anon;
grant execute on function public.review_question_slice_v18(bigint,jsonb) to authenticated;
;

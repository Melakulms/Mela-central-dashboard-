-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815170532
create table if not exists private.mela_question_review_decisions_v18 (
  slice_id bigint not null references private.mela_question_review_slices_v18(id) on delete cascade,
  question_id uuid not null references public.mela_question_bank(id) on delete cascade,
  reviewer_id uuid not null references public.profiles(id) on delete cascade,
  decision text not null check (decision in ('approved','changes_required')),
  note text,
  reviewed_at timestamptz not null default now(),
  primary key(slice_id,question_id)
);
revoke all on private.mela_question_review_decisions_v18 from public,anon,authenticated;
grant select,insert,update,delete on private.mela_question_review_decisions_v18 to service_role;

create or replace function private.question_reviewer_allowed_v18(p_uid uuid,p_program_key text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=p_uid and p.role='admin')
 or exists(
   select 1 from public.educator_profiles e join public.mela_learning_programs lp on lp.program_key=p_program_key
   where e.user_id=p_uid and e.verified and e.active
     and (lp.subject_key=any(coalesce(e.subject_areas,'{}'::text[])) or lp.subject_title=any(coalesce(e.subject_areas,'{}'::text[])))
 );
$$;
revoke all on function private.question_reviewer_allowed_v18(uuid,text) from public,anon,authenticated;
grant execute on function private.question_reviewer_allowed_v18(uuid,text) to service_role;

create or replace function public.get_question_review_queue_v18(p_program_key text default null,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_limit int:=least(greatest(coalesce(p_limit,50),1),100); begin
 if v_uid is null then raise exception 'authentication required'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('slice_id',s.id,'program_key',s.program_key,'grade_level',p.grade_level,'subject_title',p.subject_title,'track_key',p.track_key,'slice_number',s.slice_number,'question_count',s.question_count,'status',s.status,'assigned_to',s.assigned_to,'reviewed_at',s.reviewed_at) order by p.grade_level,p.subject_title,s.slice_number)
 from private.mela_question_review_slices_v18 s join public.mela_learning_programs p on p.program_key=s.program_key
 where (p_program_key is null or s.program_key=p_program_key) and private.question_reviewer_allowed_v18(v_uid,s.program_key)
 limit v_limit),'[]'::jsonb);
end $$;
revoke all on function public.get_question_review_queue_v18(text,integer) from public,anon;
grant execute on function public.get_question_review_queue_v18(text,integer) to authenticated;

create or replace function public.get_question_review_slice_v18(p_slice_id bigint)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); s private.mela_question_review_slices_v18%rowtype; begin
 if v_uid is null then raise exception 'authentication required'; end if;
 select * into s from private.mela_question_review_slices_v18 where id=p_slice_id;
 if not found then raise exception 'review slice not found'; end if;
 if not private.question_reviewer_allowed_v18(v_uid,s.program_key) then raise exception 'verified educator subject access required'; end if;
 return jsonb_build_object('slice_id',s.id,'program_key',s.program_key,'slice_number',s.slice_number,'status',s.status,'questions',coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'question_number',q.question_number,'chapter_id',q.chapter_id,'topic_id',q.topic_id,'question_type',q.question_type,'prompt',q.prompt,'choices',q.choices,'difficulty',q.difficulty,'cognitive_level',q.cognitive_level,'access_tier',q.access_tier,'validation_status',q.validation_status,'machine_quality_score',q.machine_quality_score,'grading_kind',g.grading_kind,'correct_response',g.correct_response,'accepted_variants',g.accepted_variants,'tolerance',g.tolerance,'rationale',g.rationale,'existing_decision',(select d.decision from private.mela_question_review_decisions_v18 d where d.slice_id=s.id and d.question_id=q.id),'existing_note',(select d.note from private.mela_question_review_decisions_v18 d where d.slice_id=s.id and d.question_id=q.id)) order by q.question_number) from public.mela_question_bank q join private.mela_question_grading_v12 g on g.question_id=q.id where q.id=any(s.question_ids)),'[]'::jsonb));
end $$;
revoke all on function public.get_question_review_slice_v18(bigint) from public,anon;
grant execute on function public.get_question_review_slice_v18(bigint) to authenticated;

create or replace function public.review_question_slice_v18(p_slice_id bigint,p_decisions jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); s private.mela_question_review_slices_v18%rowtype; x jsonb; v_q uuid; v_dec text; v_total int; v_done int; v_approved int; v_changes int; begin
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
   if v_dec='approved' then update public.mela_question_bank set validation_status='educator_verified',quality_checks=quality_checks||jsonb_build_object('v18_educator_verified',true,'v18_educator_verified_at',now()),updated_at=now() where id=v_q;
   else update public.mela_question_bank set validation_status='review_required',machine_quality_score=least(machine_quality_score,60),quality_checks=quality_checks||jsonb_build_object('v18_educator_changes_required',true,'v18_educator_reviewed_at',now()),updated_at=now() where id=v_q; end if;
 end loop;
 select count(*) into v_total from unnest(s.question_ids);
 select count(*),count(*) filter(where decision='approved'),count(*) filter(where decision='changes_required') into v_done,v_approved,v_changes from private.mela_question_review_decisions_v18 where slice_id=s.id;
 update private.mela_question_review_slices_v18 set status=case when v_done=v_total and v_changes=0 then 'approved' when v_done=v_total and v_changes>0 then 'changes_required' when v_done>0 then 'in_review' else 'pending' end,reviewed_at=case when v_done=v_total then now() else reviewed_at end,updated_at=now() where id=s.id;
 update public.mela_question_review_batches b set educator_verified_count=(select count(*) from public.mela_question_bank q where q.program_key=s.program_key and q.active and q.validation_status='educator_verified'),deterministic_validated_count=(select count(*) from public.mela_question_bank q where q.program_key=s.program_key and q.active and q.validation_status in ('deterministic_validated','educator_verified')),review_status=case when exists(select 1 from public.mela_question_bank q where q.program_key=s.program_key and q.active and q.validation_status='review_required') then 'changes_required' else 'in_review' end,updated_at=now() where b.program_key=s.program_key;
 update private.mela_question_regeneration_queue_v18 r set current_mastery_count=(select count(*) from public.mela_question_bank q where q.program_key=s.program_key and q.active and q.validation_status in ('deterministic_validated','educator_verified')),questions_needed=greatest(500-(select count(*) from public.mela_question_bank q where q.program_key=s.program_key and q.active and q.validation_status in ('deterministic_validated','educator_verified')),0),updated_at=now() where r.program_key=s.program_key;
 return jsonb_build_object('slice_id',s.id,'reviewed',v_done,'approved',v_approved,'changes_required',v_changes,'total',v_total);
end $$;
revoke all on function public.review_question_slice_v18(bigint,jsonb) from public,anon;
grant execute on function public.review_question_slice_v18(bigint,jsonb) to authenticated;
;

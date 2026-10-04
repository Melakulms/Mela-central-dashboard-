-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814204850
-- Add platform kill-switch coverage to the existing diagnostic/catch-up tables.
do $$declare t text;begin foreach t in array array['learner_diagnostic_sessions','learner_diagnostic_results','learner_catchup_plans','learner_catchup_plan_items','learner_support_signals'] loop execute format('drop policy if exists mela_master_gate on public.%I',t);execute format('create policy mela_master_gate on public.%I as restrictive for all to anon,authenticated using (public.platform_feature_available(''platform_live'') or private.is_admin_user()) with check (public.platform_feature_available(''platform_live'') or private.is_admin_user())',t);end loop;end$$;

grant select on public.learner_diagnostic_sessions,public.learner_diagnostic_results,public.learner_catchup_plans,public.learner_catchup_plan_items,public.learner_support_signals to authenticated;
grant select,insert,update,delete on public.learner_diagnostic_sessions to authenticated;

create or replace function private.run_my_evidence_diagnostic(p_diagnostic_type text default 'checkpoint')
returns public.learner_diagnostic_sessions language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid());v_stage text;v_session public.learner_diagnostic_sessions%rowtype;v_weak int;v_avg numeric;begin
 if v_uid is null then raise exception 'authentication required';end if;
 if p_diagnostic_type not in ('baseline','catchup','checkpoint','transition') then raise exception 'invalid diagnostic type';end if;
 select education_stage_key into v_stage from public.profiles where id=v_uid and role='student';if v_stage is null then raise exception 'learner education stage required';end if;
 insert into public.learner_diagnostic_sessions(user_id,stage_key,diagnostic_type,status,summary) values(v_uid,v_stage,p_diagnostic_type,'in_progress','{}'::jsonb) returning * into v_session;
 insert into public.learner_diagnostic_results(session_id,competency_id,score,confidence,evidence_count,estimated_level)
 select v_session.id,c.id,coalesce(m.mastery_score,0),least(1,coalesce(m.confidence_score,0)/100.0),coalesce(m.evidence_count,0),coalesce(m.mastery_level,'not_started')
 from public.learning_competencies c left join public.learner_mastery_records m on m.competency_id=c.id and m.user_id=v_uid
 where c.stage_key=v_stage and c.content_status<>'retired';
 select count(*) filter(where score<65),coalesce(round(avg(score),2),0) into v_weak,v_avg from public.learner_diagnostic_results where session_id=v_session.id;
 update public.learner_diagnostic_sessions set status='completed',completed_at=now(),summary=jsonb_build_object('method','evidence_snapshot','average_score',v_avg,'competencies_below_65',v_weak,'note','This diagnostic summarizes existing Mela evidence. It is not yet an adaptive standardized diagnostic test.') where id=v_session.id returning * into v_session;
 delete from public.learner_support_signals where learner_id=v_uid and source='evidence_diagnostic' and status='open';
 insert into public.learner_support_signals(learner_id,competency_id,signal_type,severity,title,explanation,status,source)
 select v_uid,r.competency_id,'mastery_gap',case when r.score<40 then 'priority' else 'attention' end,'Mastery support recommended',c.title||' is currently at '||round(r.score)||'% based on available evidence.','open','evidence_diagnostic'
 from public.learner_diagnostic_results r join public.learning_competencies c on c.id=r.competency_id where r.session_id=v_session.id and r.score<65;
 return v_session;end;$$;
revoke all on function private.run_my_evidence_diagnostic(text) from public,anon;grant execute on function private.run_my_evidence_diagnostic(text) to authenticated,service_role;
create or replace function public.run_my_evidence_diagnostic(p_diagnostic_type text default 'checkpoint') returns public.learner_diagnostic_sessions language sql set search_path='' as $$select * from private.run_my_evidence_diagnostic(p_diagnostic_type);$$;
revoke all on function public.run_my_evidence_diagnostic(text) from public,anon;grant execute on function public.run_my_evidence_diagnostic(text) to authenticated,service_role;

create or replace function private.generate_my_catchup_plan(p_duration_weeks integer default 6)
returns public.learner_catchup_plans language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid());v_stage text;v_plan public.learner_catchup_plans%rowtype;v_diag uuid;begin
 if v_uid is null then raise exception 'authentication required';end if;if p_duration_weeks<2 or p_duration_weeks>12 then raise exception 'catch-up duration must be 2 to 12 weeks';end if;
 select education_stage_key into v_stage from public.profiles where id=v_uid and role='student';if v_stage is null then raise exception 'learner education stage required';end if;
 select id into v_diag from public.learner_diagnostic_sessions where user_id=v_uid and stage_key=v_stage and status='completed' order by completed_at desc nulls last limit 1;
 if v_diag is null then perform private.run_my_evidence_diagnostic('catchup');select id into v_diag from public.learner_diagnostic_sessions where user_id=v_uid and stage_key=v_stage and status='completed' order by completed_at desc nulls last limit 1;end if;
 update public.learner_catchup_plans set status='cancelled' where user_id=v_uid and status='active';
 insert into public.learner_catchup_plans(user_id,stage_key,title,rationale,duration_weeks,status) values(v_uid,v_stage,'Mela Catch-Up Plan','Prioritizes the weakest competencies identified from current Mela evidence. Recheck mastery as new evidence is added.',p_duration_weeks,'active') returning * into v_plan;
 insert into public.learner_catchup_plan_items(plan_id,competency_id,week_number,priority,target_score,status,notes)
 select v_plan.id,r.competency_id,least(p_duration_weeks,greatest(1,row_number() over(order by r.score asc,r.evidence_count asc))::int),least(5,greatest(1,ceil((65-r.score)/13.0)::int)),greatest(70,c.target_score),'planned','Current evidence score '||round(r.score)||'%. Build practice/project/teacher evidence and recheck mastery.'
 from public.learner_diagnostic_results r join public.learning_competencies c on c.id=r.competency_id where r.session_id=v_diag and r.score<75 order by r.score asc limit least(12,p_duration_weeks*2);
 return v_plan;end;$$;
revoke all on function private.generate_my_catchup_plan(integer) from public,anon;grant execute on function private.generate_my_catchup_plan(integer) to authenticated,service_role;
create or replace function public.generate_my_catchup_plan(p_duration_weeks integer default 6) returns public.learner_catchup_plans language sql set search_path='' as $$select * from private.generate_my_catchup_plan(p_duration_weeks);$$;
revoke all on function public.generate_my_catchup_plan(integer) from public,anon;grant execute on function public.generate_my_catchup_plan(integer) to authenticated,service_role;

create or replace function public.get_my_learning_support() returns jsonb language sql stable security invoker set search_path='' as $$
select jsonb_build_object('latest_diagnostic',coalesce((select jsonb_build_object('id',s.id,'diagnostic_type',s.diagnostic_type,'completed_at',s.completed_at,'summary',s.summary,'results',(select coalesce(jsonb_agg(jsonb_build_object('competency_id',r.competency_id,'title',c.title,'domain',c.domain_title,'score',r.score,'confidence',r.confidence,'evidence_count',r.evidence_count,'estimated_level',r.estimated_level) order by r.score asc),'[]'::jsonb) from public.learner_diagnostic_results r join public.learning_competencies c on c.id=r.competency_id where r.session_id=s.id)) from public.learner_diagnostic_sessions s where s.user_id=(select auth.uid()) and s.status='completed' order by s.completed_at desc nulls last limit 1),'null'::jsonb),'active_catchup_plan',coalesce((select jsonb_build_object('id',p.id,'title',p.title,'rationale',p.rationale,'duration_weeks',p.duration_weeks,'created_at',p.created_at,'items',(select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'week_number',i.week_number,'priority',i.priority,'target_score',i.target_score,'status',i.status,'competency_id',i.competency_id,'title',c.title,'domain',c.domain_title,'notes',i.notes) order by i.week_number,i.priority desc),'[]'::jsonb) from public.learner_catchup_plan_items i join public.learning_competencies c on c.id=i.competency_id where i.plan_id=p.id)) from public.learner_catchup_plans p where p.user_id=(select auth.uid()) and p.status='active' order by p.created_at desc limit 1),'null'::jsonb),'support_signals',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'signal_type',s.signal_type,'severity',s.severity,'title',s.title,'explanation',s.explanation,'competency_id',s.competency_id,'status',s.status,'created_at',s.created_at) order by case s.severity when 'priority' then 1 when 'attention' then 2 else 3 end,s.created_at desc) from public.learner_support_signals s where s.learner_id=(select auth.uid()) and s.status in ('open','acknowledged')),'[]'::jsonb));$$;
revoke all on function public.get_my_learning_support() from public,anon;grant execute on function public.get_my_learning_support() to authenticated,service_role;
;

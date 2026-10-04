-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814204539
create or replace function private.set_my_mela_next_goal(p_goal_type text,p_goal_title text,p_career_path_id uuid default null,p_target_date date default null)
returns public.mela_transition_plans language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid());v_stage text;v_plan public.mela_transition_plans%rowtype;v_allowed boolean:=false;begin
 if v_uid is null then raise exception 'authentication required';end if;select education_stage_key into v_stage from public.profiles where id=v_uid and role='student';if v_stage is null then raise exception 'learner education stage required';end if;
 v_allowed:=case when v_stage in ('school_1_6','school_7_8') then p_goal_type='next_grade' when v_stage='school_9_10' then p_goal_type in ('next_grade','college_tvet','university','career_path') when v_stage='school_11_12' then p_goal_type in ('college_tvet','university','career_path','scholarship','employment','entrepreneurship') when v_stage in ('college_tvet','university') then p_goal_type in ('career_path','scholarship','employment','entrepreneurship','university','college_tvet') else false end;
 if not v_allowed then raise exception 'goal type is not appropriate for your education stage';end if;
 if p_goal_type='employment' and v_stage='school_11_12' and not exists(select 1 from public.user_policy_acknowledgements a join public.policy_documents d on d.policy_key=a.policy_key and d.version=a.policy_version where a.user_id=v_uid and a.accepted and a.revoked_at is null and d.policy_key='adult_work_eligibility' and d.status='active') then raise exception '18+ work eligibility acknowledgement required';end if;
 update public.mela_transition_plans set status='archived',updated_at=now() where user_id=v_uid and status='active';
 if nullif(trim(p_goal_title),'') is null then raise exception 'goal title required';end if;
 insert into public.mela_transition_plans(user_id,goal_type,goal_title,career_path_id,target_date) values(v_uid,p_goal_type,trim(p_goal_title),p_career_path_id,p_target_date) returning * into v_plan;
 insert into public.mela_transition_steps(plan_id,step_order,step_type,title,description,route_key) values
 (v_plan.id,1,'research','Understand your starting point','Review your Mastery Map and current evidence.','mastery'),
 (v_plan.id,2,'research','Explore possible routes','Use the Opportunity Graph to compare realistic routes.','opportunity-graph'),
 (v_plan.id,3,'project','Build evidence','Complete a project or learning activity that strengthens the capabilities you need.','passport'),
 (v_plan.id,4,'verify','Prove progress','Add verified evidence through Practice, assessment, project review or teacher observation.','passport'),
 (v_plan.id,5,'prepare','Prepare the next move','Prepare applications, scholarship materials, placement evidence or the next education step.','mela-next');return v_plan;end;$$;
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260827194532
insert into public.mela_ai_tools(tool_key,name,description,risk_level) values
('get_current_user','Get current user','Reads the authenticated user profile only.',1),
('search_courses','Search courses','Searches published MELA courses.',1),
('search_jobs','Search jobs','Searches published MELA opportunities/jobs.',1),
('search_scholarships','Search scholarships','Searches published scholarship opportunities.',1),
('get_student_progress','Get student progress','Reads authorized learning progress.',1),
('create_task','Create AI task','Creates a controlled workflow task; risky actions can require approval.',2),
('admin_snapshot','Admin snapshot','Reads admin dashboard metrics for administrators.',2)
on conflict(tool_key) do update set name=excluded.name,description=excluded.description,risk_level=excluded.risk_level,updated_at=now();
insert into public.mela_ai_agent_tools(agent_id,tool_id)
select a.id,t.id from public.mela_ai_agents a cross join public.mela_ai_tools t
where (a.agent_key in ('master','student','teacher','content') and t.tool_key in ('get_current_user','search_courses'))
   or (a.agent_key in ('master','job','company','career') and t.tool_key in ('get_current_user','search_jobs'))
   or (a.agent_key='scholarship' and t.tool_key in ('get_current_user','search_scholarships'))
   or (a.agent_key='parent' and t.tool_key in ('get_current_user','get_student_progress'))
   or (a.agent_key='admin' and t.tool_key in ('get_current_user','admin_snapshot'))
on conflict do nothing;
;

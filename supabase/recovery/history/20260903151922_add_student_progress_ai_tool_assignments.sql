-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260903151922
insert into public.mela_ai_agent_tools(agent_id,tool_id) select a.id,t.id from public.mela_ai_agents a cross join public.mela_ai_tools t where a.agent_key='student' and t.tool_key='get_student_progress' and not exists (select 1 from public.mela_ai_agent_tools x where x.agent_id=a.id and x.tool_id=t.id);
;

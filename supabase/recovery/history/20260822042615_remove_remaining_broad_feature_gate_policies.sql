-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822042615
drop policy if exists mela_gate_platform_live on public.audience_feature_matrix;
drop policy if exists mela_gate_academy on public.career_paths;
drop policy if exists mela_gate_platform_live on public.career_paths;
drop policy if exists mela_gate_platform_live on public.education_audience_stages;
drop policy if exists mela_master_gate on public.mela_transition_plans;
drop policy if exists mela_master_gate on public.mela_transition_steps;
drop policy if exists mela_master_gate on public.opportunity_graph_edges;
drop policy if exists mela_master_gate on public.opportunity_graph_nodes;
drop policy if exists mela_gate_academy on public.path_module_resources;
drop policy if exists mela_gate_platform_live on public.path_module_resources;
drop policy if exists mela_gate_academy on public.path_modules;
drop policy if exists mela_gate_platform_live on public.path_modules;
drop policy if exists mela_gate_platform_live on public.platform_audience_sections;
drop policy if exists mela_gate_platform_live on public.platform_audience_subsections;
drop policy if exists mela_gate_platform_live on public.platform_events;
drop policy if exists mela_gate_platform_live on public.practice_topics;
drop policy if exists mela_gate_practice on public.practice_topics;
drop policy if exists mela_gate_platform_live on public.skills;
;

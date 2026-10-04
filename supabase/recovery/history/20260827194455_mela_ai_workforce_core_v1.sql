-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260827194455
create schema if not exists private;

create table if not exists public.mela_ai_agents (
 id uuid primary key default gen_random_uuid(),
 agent_key text unique not null,
 name text not null,
 domain text not null,
 description text,
 system_prompt text,
 enabled boolean not null default true,
 autonomy_level smallint not null default 1 check (autonomy_level between 1 and 3),
 max_steps integer not null default 8,
 timeout_seconds integer not null default 60,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.mela_ai_tools (
 id uuid primary key default gen_random_uuid(),
 tool_key text unique not null,
 name text not null,
 description text,
 input_schema jsonb not null default '{}'::jsonb,
 output_schema jsonb not null default '{}'::jsonb,
 required_roles public.user_role[] not null default '{}'::public.user_role[],
 risk_level smallint not null default 1 check (risk_level between 1 and 3),
 enabled boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.mela_ai_agent_tools (
 agent_id uuid not null references public.mela_ai_agents(id) on delete cascade,
 tool_id uuid not null references public.mela_ai_tools(id) on delete cascade,
 primary key(agent_id,tool_id)
);

create table if not exists public.mela_ai_sessions (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 agent_id uuid references public.mela_ai_agents(id),
 title text,
 context jsonb not null default '{}'::jsonb,
 status text not null default 'active' check(status in ('active','archived','failed')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.mela_ai_messages (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.mela_ai_sessions(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null check(role in ('user','assistant','system','tool')),
 content text,
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);

create table if not exists public.mela_ai_tasks (
 id uuid primary key default gen_random_uuid(),
 created_by uuid not null references auth.users(id),
 assigned_agent_id uuid references public.mela_ai_agents(id),
 assigned_user_id uuid references auth.users(id),
 parent_task_id uuid references public.mela_ai_tasks(id),
 title text not null,
 description text,
 priority smallint not null default 3 check(priority between 1 and 5),
 status text not null default 'queued' check(status in ('queued','running','waiting_approval','blocked','completed','failed','cancelled')),
 approval_level smallint not null default 1 check(approval_level between 1 and 3),
 approval_status text not null default 'not_required' check(approval_status in ('not_required','pending','approved','rejected')),
 deadline timestamptz,
 result jsonb,
 error_message text,
 created_at timestamptz not null default now(),
 started_at timestamptz,
 completed_at timestamptz,
 updated_at timestamptz not null default now()
);

create table if not exists public.mela_ai_approvals (
 id uuid primary key default gen_random_uuid(),
 task_id uuid not null references public.mela_ai_tasks(id) on delete cascade,
 requested_by uuid not null references auth.users(id),
 reviewed_by uuid references auth.users(id),
 level smallint not null check(level between 2 and 3),
 action_type text not null,
 action_payload jsonb not null default '{}'::jsonb,
 status text not null default 'pending' check(status in ('pending','approved','rejected','expired')),
 review_note text,
 created_at timestamptz not null default now(),
 reviewed_at timestamptz
);

create table if not exists public.mela_ai_runs (
 id uuid primary key default gen_random_uuid(),
 session_id uuid references public.mela_ai_sessions(id) on delete set null,
 task_id uuid references public.mela_ai_tasks(id) on delete set null,
 agent_id uuid references public.mela_ai_agents(id),
 user_id uuid not null references auth.users(id) on delete cascade,
 model text,
 route_class text,
 step_count integer not null default 0,
 status text not null default 'running' check(status in ('running','completed','failed','timeout','cancelled')),
 input_tokens integer,
 output_tokens integer,
 latency_ms integer,
 error_message text,
 created_at timestamptz not null default now(),
 completed_at timestamptz
);

create table if not exists public.mela_ai_tool_calls (
 id uuid primary key default gen_random_uuid(),
 run_id uuid not null references public.mela_ai_runs(id) on delete cascade,
 tool_id uuid not null references public.mela_ai_tools(id),
 user_id uuid not null references auth.users(id) on delete cascade,
 input jsonb not null default '{}'::jsonb,
 output jsonb,
 status text not null default 'running' check(status in ('running','completed','failed','denied')),
 error_message text,
 created_at timestamptz not null default now(),
 completed_at timestamptz
);

create table if not exists public.mela_ai_memory (
 id uuid primary key default gen_random_uuid(),
 user_id uuid references auth.users(id) on delete cascade,
 memory_scope text not null check(memory_scope in ('short_term','user','platform','business')),
 memory_key text not null,
 content jsonb not null,
 source text,
 approved boolean not null default false,
 expires_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(user_id,memory_scope,memory_key)
);

create table if not exists public.mela_ai_model_routes (
 id uuid primary key default gen_random_uuid(),
 route_class text unique not null check(route_class in ('simple','normal','complex')),
 provider text not null,
 model_name text not null,
 enabled boolean not null default true,
 max_output_tokens integer,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.mela_ai_security_events (
 id uuid primary key default gen_random_uuid(),
 user_id uuid references auth.users(id) on delete set null,
 event_type text not null,
 severity text not null default 'info' check(severity in ('info','low','medium','high','critical')),
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);

create index if not exists idx_mela_ai_sessions_user on public.mela_ai_sessions(user_id,updated_at desc);
create index if not exists idx_mela_ai_messages_session on public.mela_ai_messages(session_id,created_at);
create index if not exists idx_mela_ai_tasks_status on public.mela_ai_tasks(status,priority,created_at);
create index if not exists idx_mela_ai_runs_user on public.mela_ai_runs(user_id,created_at desc);
create index if not exists idx_mela_ai_security_events_created on public.mela_ai_security_events(created_at desc);

alter table public.mela_ai_agents enable row level security;
alter table public.mela_ai_tools enable row level security;
alter table public.mela_ai_agent_tools enable row level security;
alter table public.mela_ai_sessions enable row level security;
alter table public.mela_ai_messages enable row level security;
alter table public.mela_ai_tasks enable row level security;
alter table public.mela_ai_approvals enable row level security;
alter table public.mela_ai_runs enable row level security;
alter table public.mela_ai_tool_calls enable row level security;
alter table public.mela_ai_memory enable row level security;
alter table public.mela_ai_model_routes enable row level security;
alter table public.mela_ai_security_events enable row level security;

create policy mela_ai_agents_read on public.mela_ai_agents for select to authenticated using(enabled or private.is_admin_user());
create policy mela_ai_agents_admin on public.mela_ai_agents for all to authenticated using(private.is_admin_user()) with check(private.is_admin_user());
create policy mela_ai_tools_read on public.mela_ai_tools for select to authenticated using(enabled or private.is_admin_user());
create policy mela_ai_tools_admin on public.mela_ai_tools for all to authenticated using(private.is_admin_user()) with check(private.is_admin_user());
create policy mela_ai_agent_tools_read on public.mela_ai_agent_tools for select to authenticated using(true);
create policy mela_ai_agent_tools_admin on public.mela_ai_agent_tools for all to authenticated using(private.is_admin_user()) with check(private.is_admin_user());
create policy mela_ai_sessions_owner on public.mela_ai_sessions for all to authenticated using(user_id=(select auth.uid()) or private.is_admin_user()) with check(user_id=(select auth.uid()) or private.is_admin_user());
create policy mela_ai_messages_owner on public.mela_ai_messages for all to authenticated using(user_id=(select auth.uid()) or private.is_admin_user()) with check(user_id=(select auth.uid()) or private.is_admin_user());
create policy mela_ai_tasks_owner_or_admin on public.mela_ai_tasks for select to authenticated using(created_by=(select auth.uid()) or assigned_user_id=(select auth.uid()) or private.is_admin_user());
create policy mela_ai_tasks_insert on public.mela_ai_tasks for insert to authenticated with check(created_by=(select auth.uid()));
create policy mela_ai_tasks_update on public.mela_ai_tasks for update to authenticated using(created_by=(select auth.uid()) or assigned_user_id=(select auth.uid()) or private.is_admin_user()) with check(created_by=(select auth.uid()) or assigned_user_id=(select auth.uid()) or private.is_admin_user());
create policy mela_ai_approvals_requester_or_admin on public.mela_ai_approvals for select to authenticated using(requested_by=(select auth.uid()) or private.is_admin_user());
create policy mela_ai_approvals_admin_update on public.mela_ai_approvals for update to authenticated using(private.is_admin_user()) with check(private.is_admin_user());
create policy mela_ai_runs_owner_or_admin on public.mela_ai_runs for select to authenticated using(user_id=(select auth.uid()) or private.is_admin_user());
create policy mela_ai_tool_calls_owner_or_admin on public.mela_ai_tool_calls for select to authenticated using(user_id=(select auth.uid()) or private.is_admin_user());
create policy mela_ai_memory_owner_or_admin on public.mela_ai_memory for all to authenticated using((user_id=(select auth.uid())) or private.is_admin_user()) with check((user_id=(select auth.uid())) or private.is_admin_user());
create policy mela_ai_model_routes_admin on public.mela_ai_model_routes for select to authenticated using(enabled or private.is_admin_user());
create policy mela_ai_model_routes_admin_write on public.mela_ai_model_routes for all to authenticated using(private.is_admin_user()) with check(private.is_admin_user());
create policy mela_ai_security_events_admin on public.mela_ai_security_events for select to authenticated using(private.is_admin_user());

insert into public.mela_ai_agents(agent_key,name,domain,description,autonomy_level) values
('master','MELA Master Agent','orchestration','Routes requests, coordinates agents and enforces action policy.',1),
('student','Student Agent','education','Personalized academic support and learning plans.',1),
('teacher','Teacher Agent','education','Lesson, assessment and teaching support.',1),
('parent','Parent Agent','education','Authorized learner progress and family learning support.',1),
('content','Content Agent','education','Approved MELA content search, organization and generation.',1),
('career','Career Agent','career','Career guidance and skill-gap planning.',1),
('job','Job Agent','employment','Vacancy and candidate matching support.',1),
('company','Company Agent','employment','Employer vacancy and recruiting workflow support.',1),
('scholarship','Scholarship Agent','opportunities','Verified scholarship discovery and application planning.',1),
('marketing','Marketing Agent','business','Marketing strategy and campaign planning.',2),
('growth','Growth Agent','business','Acquisition, retention and growth experiments.',2),
('research','Market Research Agent','business','Market and competitor research with source awareness.',1),
('strategy','Business Strategy Agent','business','Business model, pricing and strategic analysis.',1),
('sales','Sales Agent','business','Sales pipeline and conversion support.',2),
('partnership','Partnership Agent','business','Partnership research and outreach drafting.',2),
('finance','Finance Agent','organization','Financial analysis and forecasting; no high-value transactions.',1),
('hr','HR Agent','organization','HR workflow assistance without final employment decisions.',1),
('operations','Operations Agent','organization','SOPs, workflows and bottleneck analysis.',2),
('project','Project Manager Agent','organization','Task planning and multi-agent coordination.',2),
('product','Product Manager Agent','technology','Product requirements and prioritization.',1),
('technology','Technology Agent','technology','Technical analysis and development assistance.',1),
('qa','QA Agent','technology','Testing and release verification.',2),
('security','Security Agent','security','Security monitoring and permission-risk analysis.',2),
('analytics','Data Analytics Agent','analytics','KPI and platform analytics.',1),
('support','Customer Support Agent','support','24/7 user support and escalation.',1),
('admin','Admin AI Agent','administration','Admin-only platform intelligence and controls.',2)
on conflict(agent_key) do update set name=excluded.name,domain=excluded.domain,description=excluded.description,autonomy_level=excluded.autonomy_level,updated_at=now();

insert into public.mela_ai_model_routes(route_class,provider,model_name,max_output_tokens) values
('simple','local','local-small',512),('normal','local','local-medium',1536),('complex','local','local-large',4096)
on conflict(route_class) do nothing;

;

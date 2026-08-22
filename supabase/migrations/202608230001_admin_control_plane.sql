create schema if not exists admin;

revoke all on schema admin from public;
revoke all on schema admin from anon;
revoke all on schema admin from authenticated;
grant usage on schema admin to service_role;

audit_action text;

create table if not exists admin.roles (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  description text,
  is_privileged boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists admin.permissions (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists admin.role_permissions (
  role_id uuid not null references admin.roles(id) on delete cascade,
  permission_id uuid not null references admin.permissions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_id)
);

create table if not exists admin.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role_id uuid not null references admin.roles(id),
  mfa_required boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists admin.access_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  requested_role_id uuid not null references admin.roles(id),
  reason text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists admin.audit_log (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_role text,
  action text not null,
  target_schema text,
  target_table text,
  target_id text,
  before_data jsonb,
  after_data jsonb,
  metadata jsonb not null default '{}'::jsonb,
  request_id text,
  created_at timestamptz not null default now()
);

create index if not exists admin_audit_log_created_at_idx on admin.audit_log(created_at desc);
create index if not exists admin_audit_log_actor_idx on admin.audit_log(actor_user_id, created_at desc);
create index if not exists admin_access_requests_status_idx on admin.access_requests(status, created_at desc);

insert into admin.roles(key,name,description) values
 ('super_admin','Super Admin','Full central administration access'),
 ('platform_admin','Platform Admin','Operational administration without super-admin account controls'),
 ('moderator','Moderator','Content, safety and support moderation'),
 ('finance_admin','Finance Admin','Payments, escrow, payouts and financial operations'),
 ('content_admin','Content Admin','Curriculum and content operations')
on conflict (key) do nothing;

insert into admin.permissions(key,name,description) values
 ('dashboard.read','Read platform dashboard','View operational metrics'),
 ('users.read','Read users','Search and inspect users'),
 ('users.manage','Manage users','Verify, suspend and recover accounts'),
 ('authorization.manage','Manage authorization','Edit roles and permissions'),
 ('audit.read','Read audit log','Inspect administrative activity'),
 ('content.manage','Manage content','Create, review and publish content'),
 ('employers.manage','Manage employers','Verify employers and listings'),
 ('finance.manage','Manage finance','Operate payments, escrow and payouts'),
 ('support.manage','Manage support','Resolve tickets and disputes'),
 ('moderation.manage','Manage moderation','Moderate flagged content'),
 ('analytics.read','Read analytics','View and export analytics'),
 ('system.manage','Manage system','Feature flags and platform configuration')
on conflict (key) do nothing;

insert into admin.role_permissions(role_id,permission_id)
select r.id,p.id from admin.roles r cross join admin.permissions p where r.key='super_admin'
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_id)
select r.id,p.id from admin.roles r join admin.permissions p on p.key in ('dashboard.read','users.read','users.manage','employers.manage','support.manage','analytics.read') where r.key='platform_admin'
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_id)
select r.id,p.id from admin.roles r join admin.permissions p on p.key in ('dashboard.read','moderation.manage','support.manage') where r.key='moderator'
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_id)
select r.id,p.id from admin.roles r join admin.permissions p on p.key in ('dashboard.read','finance.manage','analytics.read') where r.key='finance_admin'
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_id)
select r.id,p.id from admin.roles r join admin.permissions p on p.key in ('dashboard.read','content.manage','analytics.read') where r.key='content_admin'
on conflict do nothing;

comment on schema admin is 'Private authorization and audit control plane for MELA Central Admin. Never expose through PostgREST.';
comment on table admin.audit_log is 'Immutable administrative audit trail. Writes are performed only by trusted server-side admin APIs.';

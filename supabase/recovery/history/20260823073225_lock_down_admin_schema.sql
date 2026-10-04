-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260823073225
alter table admin.access_requests enable row level security;
alter table admin.admin_users enable row level security;
alter table admin.audit_log enable row level security;
alter table admin.permissions enable row level security;
alter table admin.role_permissions enable row level security;
alter table admin.roles enable row level security;

revoke all on admin.access_requests from anon, authenticated;
revoke all on admin.admin_users from anon, authenticated;
revoke all on admin.audit_log from anon, authenticated;
revoke all on admin.permissions from anon, authenticated;
revoke all on admin.role_permissions from anon, authenticated;
revoke all on admin.roles from anon, authenticated;

;

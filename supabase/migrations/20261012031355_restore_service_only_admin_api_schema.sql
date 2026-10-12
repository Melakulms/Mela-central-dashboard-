-- The deployed admin Edge Functions use service_role with Accept-Profile: admin.
-- PostgREST previously exposed only public,graphql_public and returned PGRST106
-- even for the service role, which the gateway mislabeled as access denied.
-- No user assignments, grants, policies, MFA requirements or data are changed.
-- This documented role override owns the exposed-schema list; to hand management
-- back to Dashboard, configure the same list there, then RESET pgrst.db_schemas
-- on authenticator and NOTIFY pgrst, 'reload config'.
do $$
begin
  if has_schema_privilege('anon','admin','usage')
    or has_schema_privilege('authenticated','admin','usage') then
    raise exception 'Refusing exposure: client role has admin schema usage';
  end if;
  if not has_schema_privilege('service_role','admin','usage')
    or not has_table_privilege('service_role','admin.admin_users','select') then
    raise exception 'Missing existing service-only registry grants';
  end if;
  if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='admin' and c.relkind in ('r','p') and not c.relrowsecurity) then
    raise exception 'Refusing exposure: admin table without RLS';
  end if;
  if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    cross join unnest(array['anon','authenticated']) r
    where n.nspname='admin' and c.relkind in ('r','p','v')
      and has_table_privilege(r,c.oid,'select,insert,update,delete')) then
    raise exception 'Refusing exposure: client role has admin table grants';
  end if;
end $$;
alter role authenticator set pgrst.db_schemas = 'public, graphql_public, admin';
notify pgrst, 'reload config';
notify pgrst, 'reload schema';

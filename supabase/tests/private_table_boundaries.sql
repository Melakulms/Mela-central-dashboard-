begin;
do $test$
declare t record; blocked boolean;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='private' and c.relkind='r' loop
    if not (select relrowsecurity from pg_class where oid=format('private.%I',t.relname)::regclass) then
      raise exception 'Private table % lacks RLS',t.relname;
    end if;
    execute 'set local role authenticated';
    blocked:=false;
    begin execute format('select 1 from private.%I limit 1',t.relname);
    exception when insufficient_privilege then blocked:=true; end;
    execute 'reset role';
    if not blocked then raise exception 'Browser can directly read private table %',t.relname; end if;
    if has_table_privilege('anon',format('private.%I',t.relname),'SELECT')
      or has_table_privilege('authenticated',format('private.%I',t.relname),'INSERT,UPDATE,DELETE,TRUNCATE') then
      raise exception 'Unexpected browser grant on %',t.relname;
    end if;
  end loop;
end
$test$;
rollback;

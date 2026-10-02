begin;
do $test$
declare
 actor uuid := gen_random_uuid(); target uuid := gen_random_uuid(); role_id uuid;
 before_row jsonb; after_row jsonb; blocked boolean := false;
begin
 if has_function_privilege('authenticated','admin.apply_audited_update(uuid,text,text,jsonb,jsonb,text,jsonb)','execute') or has_function_privilege('anon','admin.apply_audited_update(uuid,text,text,jsonb,jsonb,text,jsonb)','execute') then raise exception 'Browser RPC access permitted'; end if;
 insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at) values
 (actor,actor::text||'@example.invalid','{"provider":"email"}','{"full_name":"Audit regression admin","role":"student"}',now(),now(),now()),
 (target,target::text||'@example.invalid','{"provider":"email"}','{"full_name":"Audit regression target","role":"student"}',now(),now(),now());
 select id into role_id from admin.roles where key='super_admin';
 if role_id is null then raise exception 'Test role unavailable'; end if;
 insert into admin.admin_users(user_id,role_id,active,mfa_required) values(actor,role_id,true,true);
 select to_jsonb(p) into before_row from public.profiles p where id=target;
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 execute 'set local role service_role';
 after_row:=admin.apply_audited_update(actor,'user.update',target::text,before_row,'{"account_status":"suspended"}',actor::text,'{}');
 if after_row->>'account_status'<>'suspended' then raise exception 'Update missing'; end if;
 if not exists(select 1 from admin.audit_log where request_id=actor::text and before_data=before_row and after_data @> after_row) then raise exception 'Audit missing'; end if;
 begin
  perform admin.apply_audited_update(actor,'user.update',target::text,before_row,'{"account_status":"active"}',actor::text,'{}');
 exception when serialization_failure then blocked:=true;
 end;
 if not blocked then raise exception 'Stale update accepted'; end if;
 blocked:=false;
 begin
  perform admin.apply_audited_update(actor,'user.update',target::text,after_row,'{"role":"admin"}',actor::text,'{}');
 exception when invalid_parameter_value then blocked:=true;
 end;
 if not blocked then raise exception 'Unsupported column accepted'; end if;
 blocked:=false;
 begin
  perform admin.apply_audited_update(target,'user.update',target::text,after_row,'{"account_status":"active"}',actor::text,'{}');
 exception when insufficient_privilege then blocked:=true;
 end;
 if not blocked then raise exception 'Non-admin actor accepted'; end if;
 if (select account_status from public.profiles where id=target)<>'suspended' then raise exception 'Failed update changed record'; end if;
 execute 'reset role';
end;
$test$;
rollback;

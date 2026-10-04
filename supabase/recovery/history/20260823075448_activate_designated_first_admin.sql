-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260823075448
do $$
declare
  designated_user uuid;
  super_role uuid;
  req_id uuid := gen_random_uuid();
begin
  if exists (select 1 from admin.admin_users where active=true) then
    raise exception 'active_admin_already_exists';
  end if;
  if exists (select 1 from admin.bootstrap_state where id=true and consumed_at is not null) then
    raise exception 'bootstrap_already_consumed';
  end if;
  select id into designated_user from auth.users where lower(email)=lower('melakuanteneh1@gmail.com') limit 1;
  if designated_user is null then
    raise exception 'designated_admin_auth_account_not_found';
  end if;
  select id into super_role from admin.roles where key='super_admin' and is_privileged=true limit 1;
  if super_role is null then raise exception 'super_admin_role_missing'; end if;
  insert into admin.admin_users(user_id,role_id,mfa_required,active)
  values(designated_user,super_role,true,true);
  update admin.bootstrap_state set consumed_at=now(),consumed_by=designated_user where id=true;
  insert into admin.audit_log(actor_user_id,actor_role,action,target_schema,target_table,target_id,before_data,after_data,metadata,request_id)
  values(designated_user,'bootstrap_system','first_admin_bootstrap_completed','admin','admin_users',designated_user::text,null,
    jsonb_build_object('user_id',designated_user,'role_id',super_role,'role','super_admin','mfa_required',true,'active',true),
    jsonb_build_object('bootstrap','one_time','bootstrap_locked',true,'designation','melakuanteneh1@gmail.com'),req_id);
end $$;
;

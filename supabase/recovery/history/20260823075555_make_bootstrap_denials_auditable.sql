-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260823075555
create or replace function admin.bootstrap_first_super_admin()
returns jsonb
language plpgsql
security definer
set search_path = admin, public, auth
as $$
declare
  caller uuid := auth.uid();
  caller_email text;
  super_role uuid;
  bootstrap_consumed timestamptz;
  req_id uuid := gen_random_uuid();
begin
  if caller is null then raise exception 'authentication_required'; end if;
  select email into caller_email from auth.users where id = caller;
  if lower(coalesce(caller_email,'')) <> lower('melakuanteneh1@gmail.com') then
    insert into admin.audit_log(actor_user_id,actor_role,action,target_schema,target_table,target_id,before_data,after_data,metadata,request_id)
    values(caller,'bootstrap_candidate','first_admin_bootstrap_denied','admin','admin_users',caller::text,null,null,jsonb_build_object('reason','identity_not_authorized'),req_id);
    return jsonb_build_object('success',false,'code','bootstrap_not_authorized');
  end if;
  select consumed_at into bootstrap_consumed from admin.bootstrap_state where id=true for update;
  if bootstrap_consumed is not null or exists(select 1 from admin.admin_users where active=true) then
    insert into admin.audit_log(actor_user_id,actor_role,action,target_schema,target_table,target_id,before_data,after_data,metadata,request_id)
    values(caller,'bootstrap_candidate','first_admin_bootstrap_denied','admin','bootstrap_state','true',jsonb_build_object('consumed_at',bootstrap_consumed),null,jsonb_build_object('reason','bootstrap_already_consumed_or_admin_exists'),req_id);
    return jsonb_build_object('success',false,'code','bootstrap_already_consumed');
  end if;
  select id into super_role from admin.roles where key='super_admin' and is_privileged=true limit 1;
  if super_role is null then raise exception 'super_admin_role_missing'; end if;
  insert into admin.admin_users(user_id,role_id,mfa_required,active) values(caller,super_role,true,true);
  update admin.bootstrap_state set consumed_at=now(),consumed_by=caller where id=true;
  insert into admin.audit_log(actor_user_id,actor_role,action,target_schema,target_table,target_id,before_data,after_data,metadata,request_id)
  values(caller,'bootstrap_candidate','first_admin_bootstrap_completed','admin','admin_users',caller::text,null,jsonb_build_object('user_id',caller,'role_id',super_role,'mfa_required',true,'active',true),jsonb_build_object('bootstrap','one_time','bootstrap_locked',true),req_id);
  return jsonb_build_object('success',true,'role','super_admin','mfa_required',true,'bootstrap_locked',true);
exception when unique_violation then
  insert into admin.audit_log(actor_user_id,actor_role,action,target_schema,target_table,target_id,before_data,after_data,metadata,request_id)
  values(caller,'bootstrap_candidate','first_admin_bootstrap_denied','admin','admin_users',caller::text,null,null,jsonb_build_object('reason','admin_assignment_conflict'),req_id);
  return jsonb_build_object('success',false,'code','bootstrap_conflict');
end;
$$;
revoke all on function admin.bootstrap_first_super_admin() from public,anon;
grant execute on function admin.bootstrap_first_super_admin() to authenticated;
;

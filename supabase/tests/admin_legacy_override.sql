begin;

do $test$
declare
  v_admin uuid := gen_random_uuid();
  v_super_role uuid;
  v_platform_role uuid;
  v_role uuid;
  v_blocked boolean;
begin
  insert into auth.users(
    id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at
  ) values (
    v_admin,
    v_admin::text || '@example.invalid',
    '{"provider":"email"}',
    '{"full_name":"Legacy admin boundary test","role":"student"}',
    now(),now(),now()
  );

  update public.profiles
  set role='admin', account_status='active', deleted_at=null
  where id=v_admin;

  select id into v_super_role from admin.roles where key='super_admin';
  select id into v_platform_role from admin.roles where key='platform_admin';
  if v_super_role is null or v_platform_role is null then
    raise exception 'Required admin roles are unavailable';
  end if;

  -- A browser session with only profiles.role='admin' must not receive the
  -- broad legacy override.
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_admin,'role','authenticated','aal','aal2')::text,
    true
  );
  if private.is_admin_user() then
    raise exception 'Profile role alone granted legacy admin authority';
  end if;

  insert into admin.admin_users(user_id,role_id,active,mfa_required)
  values(v_admin,v_super_role,true,true);

  -- Central membership is not enough when MFA is required.
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_admin,'role','authenticated','aal','aal1')::text,
    true
  );
  if private.is_admin_user() then
    raise exception 'AAL1 session bypassed required admin MFA';
  end if;

  -- A central super-admin with AAL2 may use legacy override paths.
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_admin,'role','authenticated','aal','aal2')::text,
    true
  );
  if not private.is_admin_user() then
    raise exception 'AAL2 central super-admin was denied';
  end if;

  -- Granular central roles must not inherit a generic superuser-style override;
  -- they are authorized through the permissioned admin API instead.
  update admin.admin_users set role_id=v_platform_role where user_id=v_admin;
  if private.is_admin_user() then
    raise exception 'Non-super central admin received broad legacy override';
  end if;

  -- Every granular role is denied the broad override.
  for v_role in select id from admin.roles where key<>'super_admin' loop
    update admin.admin_users set role_id=v_role where user_id=v_admin;
    if private.is_admin_user() then raise exception 'Granular role received legacy override'; end if;
  end loop;

  -- Active administrators cannot disable MFA at the data layer.
  v_blocked:=false;
  begin
    update admin.admin_users set role_id=v_super_role,mfa_required=false where user_id=v_admin;
  exception when check_violation then v_blocked:=true;
  end;
  if not v_blocked then raise exception 'Active administrator disabled MFA'; end if;
  update admin.admin_users set role_id=v_super_role where user_id=v_admin;

  update admin.admin_users set active=false where user_id=v_admin;
  if private.is_admin_user() then
    raise exception 'Inactive central admin retained legacy override';
  end if;
end
$test$;

rollback;

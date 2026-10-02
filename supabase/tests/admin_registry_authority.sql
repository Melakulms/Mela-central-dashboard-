-- Non-destructive regression: dedicated admin registry controls DB admin authority
-- and an MFA-required admin is never authorized at aal1.
do $test$
declare
  v_uid uuid;
  v_requires_mfa boolean;
  v_aal1 boolean;
  v_aal2 boolean;
begin
  select user_id,mfa_required into v_uid,v_requires_mfa
  from admin.admin_users where active=true limit 1;
  if v_uid is null then raise exception 'No active admin registry user'; end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_uid,'role','authenticated','aal','aal1')::text,true);
  v_aal1:=private.is_admin_user();
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_uid,'role','authenticated','aal','aal2')::text,true);
  v_aal2:=private.is_admin_user();

  if v_requires_mfa and v_aal1 then raise exception 'MFA-required admin was authorized at aal1'; end if;
  if not v_aal2 then raise exception 'Active registry admin was not authorized at aal2'; end if;
end $test$;
select 'PASS: admin registry authority respects MFA assurance' as result;

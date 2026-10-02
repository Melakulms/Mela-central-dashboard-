-- Service-only, whitelisted compare-and-swap updates and audit persistence in one transaction.
create or replace function admin.apply_audited_update(
  p_actor uuid, p_action text, p_target text, p_expected jsonb,
  p_patch jsonb, p_request_id text, p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_table text; v_key text := 'id'; v_permission text; v_columns text[];
  v_role text; v_role_id uuid; v_before jsonb; v_after jsonb; v_set text;
begin
  case p_action
    when 'user.update' then v_table := 'profiles'; v_permission := 'users.manage'; v_columns := array['account_status','email_verified','phone_verified'];
    when 'employer.review' then v_table := 'employer_registration_requests'; v_permission := 'employers.manage'; v_columns := array['status','review_notes','reviewed_by','reviewed_at','updated_at'];
    when 'opportunity.review' then v_table := 'opportunities'; v_permission := 'employers.manage'; v_columns := array['moderation_status','moderation_notes','reviewed_by','reviewed_at','updated_at','verified_active'];
    when 'report.resolve' then v_table := 'reports'; v_permission := 'moderation.manage'; v_columns := array['status','resolution_notes','assigned_to','resolved_at'];
    when 'settings.flag.update' then v_table := 'platform_feature_flags'; v_key := 'feature_key'; v_permission := 'system.manage'; v_columns := array['enabled','maintenance_message','config','updated_by','updated_at'];
    when 'commission.cancel' then v_table := 'invitation_commissions'; v_permission := 'finance.manage'; v_columns := array['status','cancelled_at','cancellation_reason'];
    else raise exception 'Unsupported audited action' using errcode = '22023';
  end case;
  select r.key, r.id into v_role, v_role_id from admin.admin_users a join admin.roles r on r.id=a.role_id where a.user_id=p_actor and a.active for share of a, r;
  if v_role is null or (v_role <> 'super_admin' and not exists (
    select 1 from admin.role_permissions rp join admin.permissions p on p.id=rp.permission_id where rp.role_id=v_role_id and p.key=v_permission
  )) then raise exception 'Permission denied' using errcode='42501'; end if;
  if p_expected is null or jsonb_typeof(p_expected)<>'object' or p_expected='{}'::jsonb
    or p_patch is null or jsonb_typeof(p_patch)<>'object' or p_patch='{}'::jsonb
    or exists (select 1 from jsonb_object_keys(p_patch) k where not k=any(v_columns))
    or p_request_id is null or length(p_request_id)>200
    or jsonb_typeof(p_metadata)<>'object'
  then raise exception 'Invalid audited update' using errcode='22023'; end if;
  if exists (select 1 from jsonb_each(p_patch) e where e.key in ('enabled','email_verified','phone_verified','verified_active') and jsonb_typeof(e.value)<>'boolean') then
    raise exception 'Boolean fields require true or false' using errcode='22023';
  end if;
  if (p_patch ? 'reviewed_by' and p_patch->>'reviewed_by' is distinct from p_actor::text)
    or (p_patch ? 'assigned_to' and p_patch->>'assigned_to' is distinct from p_actor::text)
    or (p_patch ? 'updated_by' and p_patch->>'updated_by' is distinct from p_actor::text)
  then raise exception 'Invalid actor attribution' using errcode='22023'; end if;
  execute format('select to_jsonb(t) from public.%I t where %I::text=$1 for update',v_table,v_key) into v_before using p_target;
  if v_before is null then raise exception 'Record not found' using errcode='P0002'; end if;
  if not v_before @> p_expected then raise exception 'Record changed; refresh before retrying' using errcode='40001'; end if;
  if p_action='user.update' and p_target=p_actor::text and p_patch ? 'account_status' and p_patch->>'account_status'<>'active' then
    raise exception 'Cannot deactivate current administrator' using errcode='22023';
  end if;
  if p_action='commission.cancel' and (v_before->>'status'<>'pending' or p_patch->>'status' is distinct from 'cancelled' or coalesce(length(trim(p_patch->>'cancellation_reason')),0) not between 1 and 500) then
    raise exception 'Commission cannot be cancelled' using errcode='22023';
  end if;
  select string_agg(format('%I = p.%I',k,k),', ' order by k) into v_set from jsonb_object_keys(p_patch) k;
  execute format('update public.%I t set %s from jsonb_populate_record(null::public.%I,$1) p where t.%I::text=$2 returning to_jsonb(t)',v_table,v_set,v_table,v_key) into v_after using p_patch,p_target;
  insert into admin.audit_log(actor_user_id,actor_role,action,target_schema,target_table,target_id,before_data,after_data,metadata,request_id)
    values(p_actor,v_role,p_action,'public',v_table,p_target,v_before,v_after,p_metadata || jsonb_build_object('source','mela-central-dashboard'),p_request_id);
  return v_after;
end;
$$;
revoke all on function admin.apply_audited_update(uuid,text,text,jsonb,jsonb,text,jsonb) from public, anon, authenticated;
grant execute on function admin.apply_audited_update(uuid,text,text,jsonb,jsonb,text,jsonb) to service_role;

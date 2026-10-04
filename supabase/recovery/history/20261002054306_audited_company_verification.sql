-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002054306
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
    when 'employer.verify' then v_table := 'employers'; v_permission := 'employers.manage'; v_columns := array['verified','verification_status','verification_notes','verified_by','verified_at','updated_at'];
    when 'employer.review' then v_table := 'employer_registration_requests'; v_permission := 'employers.manage'; v_columns := array['status','review_notes','reviewed_by','reviewed_at','updated_at'];
    when 'opportunity.review' then v_table := 'opportunities'; v_permission := 'employers.manage'; v_columns := array['moderation_status','moderation_notes','reviewed_by','reviewed_at','updated_at','verified_active'];
    when 'report.resolve' then v_table := 'reports'; v_permission := 'moderation.manage'; v_columns := array['status','resolution_notes','assigned_to','resolved_at'];
    when 'settings.flag.update' then v_table := 'platform_feature_flags'; v_key := 'feature_key'; v_permission := 'system.manage'; v_columns := array['enabled','maintenance_message','config','updated_by','updated_at'];
    when 'commission.cancel' then v_table := 'invitation_commissions'; v_permission := 'finance.manage'; v_columns := array['status','cancelled_at','cancellation_reason'];
    else raise exception 'Unsupported audited action' using errcode = '22023';
  end case;
  select r.key, r.id into v_role, v_role_id from admin.admin_users a join admin.roles r on r.id=a.role_id where a.user_id=p_actor and a.active;
  if v_role is null or (v_role <> 'super_admin' and not exists (
    select 1 from admin.role_permissions rp join admin.permissions p on p.id=rp.permission_id where rp.role_id=v_role_id and p.key=v_permission
  )) then raise exception 'Permission denied' using errcode='42501'; end if;
  if p_expected is null or jsonb_typeof(p_expected)<>'object' or p_expected='{}'::jsonb
    or p_patch is null or jsonb_typeof(p_patch)<>'object' or p_patch='{}'::jsonb
    or exists (select 1 from jsonb_object_keys(p_patch) k where not k=any(v_columns))
    or p_request_id is null or length(p_request_id)>200
    or jsonb_typeof(p_metadata)<>'object'
  then raise exception 'Invalid audited update' using errcode='22023'; end if;
  if exists (select 1 from jsonb_each(p_patch) e where e.key in ('enabled','email_verified','phone_verified','verified_active','verified') and jsonb_typeof(e.value)<>'boolean') then
    raise exception 'Boolean fields require true or false' using errcode='22023';
  end if;
  if (p_patch ? 'reviewed_by' and p_patch->>'reviewed_by' is distinct from p_actor::text)
    or (p_patch ? 'assigned_to' and p_patch->>'assigned_to' is distinct from p_actor::text)
    or (p_patch ? 'updated_by' and p_patch->>'updated_by' is distinct from p_actor::text)
    or (p_patch ? 'verified_by' and p_patch->>'verified_by' is distinct from p_actor::text)
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
  if p_action='employer.verify' and (p_patch->>'verification_status' not in ('verified','under_review','rejected','suspended') or (p_patch->>'verified')::boolean is distinct from (p_patch->>'verification_status'='verified') or nullif(trim(p_patch->>'verification_notes'),'') is null) then
    raise exception 'Verification decision and reason are required' using errcode='22023';
  end if;
  select string_agg(format('%I = p.%I',k,k),', ' order by k) into v_set from jsonb_object_keys(p_patch) k;
  execute format('update public.%I t set %s from jsonb_populate_record(null::public.%I,$1) p where t.%I::text=$2 returning to_jsonb(t)',v_table,v_set,v_table,v_key) into v_after using p_patch,p_target;
  insert into admin.audit_log(actor_user_id,actor_role,action,target_schema,target_table,target_id,before_data,after_data,metadata,request_id)
    values(p_actor,v_role,p_action,'public',v_table,p_target,v_before,v_after,p_metadata || jsonb_build_object('source','mela-central-dashboard'),p_request_id);
  if p_action='user.update' then
    return jsonb_build_object('id',v_after->'id','account_status',v_after->'account_status','email_verified',v_after->'email_verified','phone_verified',v_after->'phone_verified','updated_at',v_after->'updated_at');
  end if;
  return v_after;
end;
$$;
revoke all on function admin.apply_audited_update(uuid,text,text,jsonb,jsonb,text,jsonb) from public, anon, authenticated;
grant execute on function admin.apply_audited_update(uuid,text,text,jsonb,jsonb,text,jsonb) to service_role;


CREATE OR REPLACE FUNCTION private.process_employer_registration_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_uid uuid:=(select auth.uid()); v_admin boolean:=false; v_employer_id uuid; v_server boolean:=private.is_admin_user();
begin
  v_admin:=private.is_admin_user();
  if tg_op='UPDATE' and not v_admin and not v_server then
    if new.status is distinct from old.status or new.review_notes is distinct from old.review_notes or new.reviewed_by is distinct from old.reviewed_by or new.reviewed_at is distinct from old.reviewed_at or new.employer_id is distinct from old.employer_id then raise exception 'review fields are admin managed'; end if;
    if old.status not in ('pending','under_review') then raise exception 'request can no longer be edited'; end if;
  end if;
  if not v_admin then
    if tg_op='INSERT' and (new.status<>'pending' or new.review_notes is not null or new.reviewed_by is not null or new.reviewed_at is not null or new.employer_id is not null) then raise exception 'Review fields are admin managed'; end if;
    if tg_op='UPDATE' and (new.id is distinct from old.id or new.applicant_user_id is distinct from old.applicant_user_id) then raise exception 'Request identity cannot be changed'; end if;
  end if;
  new.updated_at:=now();
  if tg_op='UPDATE' and new.status in ('approved','rejected') and new.status is distinct from old.status then new.reviewed_by:=coalesce(v_uid,new.reviewed_by); new.reviewed_at:=now(); end if;
  if tg_op='UPDATE' and new.status='approved' and old.status is distinct from 'approved' then
    update public.profiles set role='employer'::public.user_role where id=new.applicant_user_id;
    if new.employer_id is null then
      insert into public.employers(owner_id,company_name,legal_name,registration_number,industry,sector_category,website,contact_email,phone_number,headquarters,description,verified,verification_status)
      values(new.applicant_user_id,new.company_name,new.legal_name,new.registration_number,new.industry,new.sector_category,new.website,new.contact_email,new.phone_number,new.headquarters,new.description,false,'pending')
      returning id into v_employer_id; new.employer_id:=v_employer_id;
    end if;
  end if;
  return new;
end;$function$
;

;

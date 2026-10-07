-- Service-only transaction boundary. Edge handler verifies the actor's Auth token and AAL2.
create or replace function public.mela_ai_admin_mutate(
 p_actor uuid,p_action text,p_target uuid,p_request_id text,
 p_enabled boolean default null,p_status text default null,p_note text default null
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 actor_role text; before_row jsonb; after_row jsonb; task_row jsonb;
 approval public.mela_ai_approvals%rowtype;
 task public.mela_ai_tasks%rowtype;
 target_table text;
begin
 select r.key into actor_role from admin.admin_users au
 join admin.roles r on r.id=au.role_id
 join public.profiles pr on pr.id=au.user_id
 where au.user_id=p_actor and au.active and au.mfa_required
 and pr.account_status='active' and pr.deleted_at is null
 and (r.key='super_admin' or exists(select 1 from admin.role_permissions rp
 join admin.permissions pe on pe.id=rp.permission_id where rp.role_id=r.id and pe.key='system.manage'));
 if actor_role is null then raise exception 'ADMIN_ACCESS_DENIED' using errcode='42501'; end if;
 if p_target is null or p_request_id is null or char_length(p_request_id)>200 then raise exception 'INVALID_REQUEST' using errcode='22023'; end if;
 if p_action='agent.toggle' then
  if p_enabled is null then raise exception 'INVALID_ENABLED' using errcode='22023'; end if;
  select to_jsonb(a) into before_row from public.mela_ai_agents a where id=p_target for update;
  if before_row is null then raise exception 'AGENT_NOT_FOUND' using errcode='P0002'; end if;
  update public.mela_ai_agents set enabled=p_enabled,updated_at=now() where id=p_target returning to_jsonb(mela_ai_agents.*) into after_row;
  target_table:='mela_ai_agents';
 elsif p_action='approval.review' then
  if p_status is null or p_status not in ('approved','rejected') or char_length(coalesce(p_note,''))>1000 then raise exception 'INVALID_REVIEW' using errcode='22023'; end if;
  select * into approval from public.mela_ai_approvals where id=p_target for update;
  if not found then raise exception 'APPROVAL_NOT_FOUND' using errcode='P0002'; end if;
  if approval.status<>'pending' then raise exception 'APPROVAL_ALREADY_REVIEWED' using errcode='40001'; end if;
  select * into task from public.mela_ai_tasks where id=approval.task_id for update;
  if not found or task.status<>'waiting_approval' or task.approval_status<>'pending' then raise exception 'TASK_NOT_AWAITING_APPROVAL' using errcode='40001'; end if;
  if approval.requested_by=p_actor then raise exception 'SELF_APPROVAL_DENIED' using errcode='42501'; end if;
  before_row:=to_jsonb(approval);
  update public.mela_ai_approvals set status=p_status,reviewed_by=p_actor,reviewed_at=now(),review_note=nullif(btrim(p_note),'') where id=p_target returning to_jsonb(mela_ai_approvals.*) into after_row;
  update public.mela_ai_tasks set approval_status=p_status,status=case when p_status='approved' then 'queued' else 'cancelled' end,updated_at=now() where id=task.id returning to_jsonb(mela_ai_tasks.*) into task_row;
  target_table:='mela_ai_approvals';
 else raise exception 'UNKNOWN_ACTION' using errcode='22023'; end if;
 insert into admin.audit_log(actor_user_id,actor_role,action,target_schema,target_table,target_id,before_data,after_data,metadata,request_id)
 values(p_actor,actor_role,'ai.'||p_action,'public',target_table,p_target::text,before_row,after_row,jsonb_build_object('source','mela-ai-admin','task_id',task.id),p_request_id);
 return jsonb_build_object('data',after_row,'task',task_row);
end $$;
revoke all on function public.mela_ai_admin_mutate(uuid,text,uuid,text,boolean,text,text) from public,anon,authenticated;
grant execute on function public.mela_ai_admin_mutate(uuid,text,uuid,text,boolean,text,text) to service_role;

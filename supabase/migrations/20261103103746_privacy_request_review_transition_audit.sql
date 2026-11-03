-- Staging migration 20261103103746; security-gated review workflow.
-- For now only pending -> in_review by MFA super admin and pending -> cancelled
-- by the owner are allowed. No deletion/export or final resolution.
create or replace function private.guard_audit_data_subject_request_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_action text;
begin
  if old.id is distinct from new.id
    or old.user_id is distinct from new.user_id
    or old.request_type is distinct from new.request_type
    or old.details is distinct from new.details
    or old.requested_at is distinct from new.requested_at
  then
    raise exception 'Request identity and submitted details are immutable'
      using errcode='42501';
  end if;

  if old.status='pending'
     and new.status='cancelled'
     and v_actor=old.user_id
     and new.handled_by is not distinct from old.handled_by
     and new.response_notes is not distinct from old.response_notes
     and new.completed_at is not distinct from old.completed_at
  then
    v_action := 'privacy.request_cancelled';
  elsif old.status='pending'
     and new.status='in_review'
     and v_actor is not null
     and coalesce((select auth.jwt()->>'aal'),'aal1')='aal2'
     and private.is_admin_user()
     and new.completed_at is not distinct from old.completed_at
     and (new.handled_by is null or new.handled_by=v_actor)
  then
    if char_length(btrim(coalesce(new.response_notes,''))) not between 12 and 500 then
      raise exception 'Review message must be 12 to 500 characters'
        using errcode='22023';
    end if;
    new.response_notes := btrim(new.response_notes);
    new.handled_by := v_actor;
    v_action := 'privacy.review_started';
  else
    raise exception 'Privacy request transition is not authorized'
      using errcode='42501';
  end if;

  new.updated_at := clock_timestamp();
  insert into admin.audit_log
      (actor_user_id,actor_role,action,target_schema,target_table,target_id,
       before_data,after_data,metadata,request_id)
  values
      (v_actor,case when v_action='privacy.review_started' then 'super_admin' else 'user' end,
       v_action,'public','data_subject_requests',old.id::text,
       jsonb_build_object('status',old.status),
       jsonb_build_object('status',new.status),
       jsonb_build_object('category',old.request_type,
                          'public_note_length',length(coalesce(new.response_notes,'')),
                          'source','privacy-request-transition'),
       old.id::text);
  return new;
end;
$function$;

revoke all on function private.guard_audit_data_subject_request_update()
  from public, anon, authenticated;
drop trigger if exists trg_guard_audit_data_subject_request_update
  on public.data_subject_requests;
create trigger trg_guard_audit_data_subject_request_update
  before update on public.data_subject_requests
  for each row execute function private.guard_audit_data_subject_request_update();

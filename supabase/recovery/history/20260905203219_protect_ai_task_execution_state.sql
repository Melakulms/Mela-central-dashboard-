-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260905203219
create or replace function private.guard_mela_ai_task_state_updates()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  uid uuid := auth.uid();
  is_admin boolean := false;
begin
  if uid is null then
    return new;
  end if;
  select exists (select 1 from public.profiles p where p.id = uid and p.role = 'admin') into is_admin;
  if is_admin then
    return new;
  end if;
  if old.created_by = uid then
    if new.created_by is distinct from old.created_by
       or new.assigned_agent_id is distinct from old.assigned_agent_id
       or new.assigned_user_id is distinct from old.assigned_user_id
       or new.approval_level is distinct from old.approval_level
       or new.approval_status is distinct from old.approval_status
       or new.status is distinct from old.status
       or new.result is distinct from old.result
       or new.error_message is distinct from old.error_message
       or new.started_at is distinct from old.started_at
       or new.completed_at is distinct from old.completed_at
       or new.retry_count is distinct from old.retry_count
       or new.max_retries is distinct from old.max_retries
       or new.verification_status is distinct from old.verification_status
       or new.verification_notes is distinct from old.verification_notes then
      raise exception 'AI task execution state is managed by the platform';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.guard_mela_ai_task_state_updates() from public, anon, authenticated;

 drop trigger if exists trg_guard_mela_ai_task_state on public.mela_ai_tasks;
create trigger trg_guard_mela_ai_task_state
before update on public.mela_ai_tasks
for each row execute function private.guard_mela_ai_task_state_updates();
;

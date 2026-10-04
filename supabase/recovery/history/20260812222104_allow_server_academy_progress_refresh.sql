-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812222104
create or replace function private.protect_career_path_enrollment()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
  -- Direct Data API writes run as authenticated. Nested trusted SECURITY DEFINER
  -- workflow writes run as the function owner and are allowed to maintain computed fields.
  if current_user='authenticated' and (select auth.uid()) is not null and not private.is_admin_user() then
    if tg_op='UPDATE' then
      if new.progress_percent is distinct from old.progress_percent
        or new.lessons_completed is distinct from old.lessons_completed
        or new.total_lessons is distinct from old.total_lessons
        or new.proctored_required is distinct from old.proctored_required
        or new.proctored_passed is distinct from old.proctored_passed
        or new.completed_at is distinct from old.completed_at
        or new.user_id is distinct from old.user_id
        or new.career_path_id is distinct from old.career_path_id then
        raise exception 'academy completion fields are server managed';
      end if;
      if new.status='completed' and old.status<>'completed' then
        raise exception 'academy completion status is server managed';
      end if;
    end if;
  end if;
  new.updated_at:=now();
  return new;
end; $$;
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812215107
-- Lesson-progress identity/timestamps are server-managed; browser users only report progress values.
revoke insert,update,delete on public.student_lesson_progress from authenticated;
grant insert (user_id,lesson_id,status,progress_percent,time_spent_seconds) on public.student_lesson_progress to authenticated;
grant update (status,progress_percent,time_spent_seconds) on public.student_lesson_progress to authenticated;
grant all on public.student_lesson_progress to service_role;

create or replace function private.normalize_student_lesson_progress()
returns trigger language plpgsql set search_path='pg_catalog','public' as $$
begin
  if tg_op='UPDATE' then
    if new.id is distinct from old.id or new.user_id is distinct from old.user_id or new.lesson_id is distinct from old.lesson_id or new.created_at is distinct from old.created_at then raise exception 'lesson progress identity fields are immutable'; end if;
  end if;
  if new.status='completed' or new.progress_percent>=100 then
    new.status:='completed'; new.progress_percent:=100; new.started_at:=coalesce(case when tg_op='UPDATE' then old.started_at end,now()); new.completed_at:=coalesce(case when tg_op='UPDATE' then old.completed_at end,now());
  elsif new.status='in_progress' or new.progress_percent>0 then
    new.status:='in_progress'; new.progress_percent:=least(new.progress_percent,99); new.started_at:=coalesce(case when tg_op='UPDATE' then old.started_at end,now()); new.completed_at:=null;
  else
    new.status:='not_started'; new.progress_percent:=0; new.time_spent_seconds:=0; new.started_at:=null; new.completed_at:=null;
  end if;
  new.last_viewed_at:=now(); new.updated_at:=now();
  if tg_op='INSERT' then new.created_at:=now(); end if;
  return new;
end;$$;
drop trigger if exists trg_normalize_student_lesson_progress on public.student_lesson_progress;
create trigger trg_normalize_student_lesson_progress before insert or update on public.student_lesson_progress for each row execute function private.normalize_student_lesson_progress();

-- Badges are earned by server-side workflows only.
revoke insert,update,delete on public.user_badges from authenticated,anon;
grant all on public.user_badges to service_role;

;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002192119
create or replace function public.guard_course_enrollment_identity()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op='UPDATE'
     and (new.user_id is distinct from old.user_id or new.course_id is distinct from old.course_id)
     and not private.is_admin_user() then
    raise exception 'Course enrollment identity is immutable for non-admin users';
  end if;
  if tg_op='UPDATE'
     and new.enrolled_at is distinct from old.enrolled_at
     and not private.is_admin_user() then
    raise exception 'Enrollment timestamp is immutable for non-admin users';
  end if;
  return new;
end;
$function$;

create or replace function public.guard_course_enrollment_integrity()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op='UPDATE' then
    if new.user_id is distinct from old.user_id
       or new.course_id is distinct from old.course_id
       or new.enrolled_at is distinct from old.enrolled_at then
      if not private.is_admin_user() then raise exception 'Enrollment identity fields are immutable'; end if;
    end if;
    if new.progress_pct < old.progress_pct and not private.is_admin_user() then
      raise exception 'Course progress cannot decrease';
    end if;
    if old.completed_at is not null
       and new.completed_at is distinct from old.completed_at
       and not private.is_admin_user() then
      raise exception 'Completed enrollment is immutable';
    end if;
    if new.progress_pct=100 and new.completed_at is null then new.completed_at=now(); end if;
  end if;
  return new;
end;
$function$;

create or replace function public.guard_course_enrollment_mutation()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op='UPDATE' and not private.is_admin_user() then
    if new.user_id is distinct from old.user_id or new.course_id is distinct from old.course_id then
      raise exception 'Course enrollment identity is immutable';
    end if;
    if new.progress_pct < old.progress_pct then raise exception 'Course progress cannot move backwards'; end if;
    if old.completed_at is not null and new.completed_at is distinct from old.completed_at then
      raise exception 'Completed enrollment is immutable';
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.guard_course_learning_mutation()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op='UPDATE' and not private.is_admin_user() then
    if new.user_id is distinct from old.user_id
       or new.course_id is distinct from old.course_id
       or new.enrolled_at is distinct from old.enrolled_at then
      raise exception 'Course enrollment identity is immutable';
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.guard_course_progress_identity()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op='UPDATE'
     and (new.user_id is distinct from old.user_id or new.lesson_id is distinct from old.lesson_id)
     and not private.is_admin_user() then
    raise exception 'Learning progress identity is immutable';
  end if;
  return new;
end;
$function$;

create or replace function public.guard_lesson_progress_integrity()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op='UPDATE'
     and (new.user_id is distinct from old.user_id
          or new.lesson_id is distinct from old.lesson_id
          or new.completed_at is distinct from old.completed_at)
     and not private.is_admin_user() then
    raise exception 'Lesson progress identity/completion fields are immutable';
  end if;
  return new;
end;
$function$;

create or replace function public.guard_learning_progress_mutation()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op='UPDATE' and not private.is_admin_user() then
    if new.user_id is distinct from old.user_id
       or new.lesson_id is distinct from old.lesson_id
       or new.completed_at is distinct from old.completed_at then
      raise exception 'Learning progress identity/completion fields are protected';
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.guard_lesson_progress_identity()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op='UPDATE' and not private.is_admin_user() then
    if new.user_id is distinct from old.user_id
       or new.lesson_id is distinct from old.lesson_id
       or new.completed_at is distinct from old.completed_at then
      raise exception 'Lesson progress identity is immutable';
    end if;
  end if;
  return new;
end;
$function$;
;

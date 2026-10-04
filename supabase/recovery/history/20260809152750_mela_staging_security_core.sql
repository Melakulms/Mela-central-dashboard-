-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260809152750
create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;

alter function public.fn_apply_coin_transaction() set search_path = '';
revoke all on function public.fn_apply_coin_transaction() from public;
revoke all on function public.fn_apply_coin_transaction() from anon;
revoke all on function public.fn_apply_coin_transaction() from authenticated;

drop policy if exists "profiles: public read of basic info" on public.profiles;
drop policy if exists "profiles: self read/write" on public.profiles;
drop policy if exists profiles_self_select on public.profiles;
drop policy if exists profiles_self_update on public.profiles;

create policy profiles_self_select on public.profiles for select to authenticated using ((select auth.uid()) = id);
create policy profiles_self_update on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create or replace function private.protect_profile_security_fields()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (select auth.uid()) is not null then
    if new.role is distinct from old.role then raise exception 'role cannot be changed by the profile owner'; end if;
    if new.coin_balance is distinct from old.coin_balance then raise exception 'coin balance cannot be changed by the profile owner'; end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_protect_profile_security_fields on public.profiles;
create trigger trg_protect_profile_security_fields before update on public.profiles for each row execute function private.protect_profile_security_fields();

create or replace function private.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, language_pref)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), nullif(split_part(coalesce(new.email,''), '@', 1), ''), 'Mela Learner'),
    'en'::public.app_language
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function private.handle_new_auth_user() from public;
revoke all on function private.handle_new_auth_user() from anon;
revoke all on function private.handle_new_auth_user() from authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function private.handle_new_auth_user();

alter table public.courses add column if not exists slug text;
alter table public.courses add column if not exists program_type text not null default 'course';
alter table public.courses add column if not exists credential_type text;
alter table public.courses add column if not exists category text;
alter table public.courses add column if not exists level text not null default 'Beginner';
alter table public.courses add column if not exists duration_minutes integer not null default 60;
alter table public.courses add column if not exists price_cents integer not null default 0;
alter table public.courses add column if not exists currency text not null default 'ETB';
alter table public.courses add column if not exists is_flagship boolean not null default false;
alter table public.courses add column if not exists featured_rank integer;
alter table public.courses add column if not exists is_published boolean not null default false;
alter table public.courses add column if not exists audience text;
alter table public.courses add column if not exists prerequisites text;
alter table public.courses add column if not exists learning_outcomes jsonb not null default '[]'::jsonb;
create unique index if not exists courses_slug_uidx on public.courses(slug) where slug is not null;
do $$ begin if not exists (select 1 from pg_constraint where conname='courses_price_nonnegative' and conrelid='public.courses'::regclass) then alter table public.courses add constraint courses_price_nonnegative check (price_cents >= 0); end if; end $$;

drop policy if exists "courses: public read" on public.courses;
drop policy if exists courses_published_read on public.courses;
create policy courses_published_read on public.courses for select to anon, authenticated using (is_published = true);

drop policy if exists "enrollments: self manage" on public.course_enrollments;
drop policy if exists enrollments_self_select on public.course_enrollments;
drop policy if exists enrollments_free_insert on public.course_enrollments;
create policy enrollments_self_select on public.course_enrollments for select to authenticated using ((select auth.uid()) = user_id);
create policy enrollments_free_insert on public.course_enrollments for insert to authenticated with check ((select auth.uid()) = user_id and exists (select 1 from public.courses c where c.id = course_id and c.is_published = true and c.price_cents = 0));

create table if not exists public.course_lessons (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  module_title text not null,
  module_position integer not null default 1,
  title text not null,
  lesson_position integer not null default 1,
  duration_minutes integer not null default 10,
  is_preview boolean not null default false,
  content_text text not null default '',
  created_at timestamptz not null default now(),
  unique(course_id, module_position, lesson_position)
);
alter table public.course_lessons enable row level security;
drop policy if exists lessons_preview_read on public.course_lessons;
drop policy if exists lessons_enrolled_read on public.course_lessons;
create policy lessons_preview_read on public.course_lessons for select to anon using (is_preview = true and exists (select 1 from public.courses c where c.id = course_id and c.is_published = true));
create policy lessons_enrolled_read on public.course_lessons for select to authenticated using (exists (select 1 from public.courses c where c.id = course_id and c.is_published = true) and (is_preview = true or exists (select 1 from public.course_enrollments e where e.course_id = course_lessons.course_id and e.user_id = (select auth.uid()))));

create table if not exists public.lesson_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  lesson_id uuid not null references public.course_lessons(id) on delete cascade,
  completed_at timestamptz not null default now(),
  unique(user_id, lesson_id)
);
alter table public.lesson_progress enable row level security;
drop policy if exists lesson_progress_self_select on public.lesson_progress;
drop policy if exists lesson_progress_self_insert on public.lesson_progress;
drop policy if exists lesson_progress_self_delete on public.lesson_progress;
create policy lesson_progress_self_select on public.lesson_progress for select to authenticated using ((select auth.uid()) = user_id);
create policy lesson_progress_self_insert on public.lesson_progress for insert to authenticated with check ((select auth.uid()) = user_id and exists (select 1 from public.course_lessons l join public.course_enrollments e on e.course_id = l.course_id where l.id = lesson_id and e.user_id = (select auth.uid())));
create policy lesson_progress_self_delete on public.lesson_progress for delete to authenticated using ((select auth.uid()) = user_id);

create table if not exists public.skill_assessment_results (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  score integer not null check (score between 0 and 100),
  level text not null check (level in ('Beginner','Intermediate','Advanced')),
  answers jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.skill_assessment_results enable row level security;
drop policy if exists assessment_self_select on public.skill_assessment_results;
drop policy if exists assessment_self_insert on public.skill_assessment_results;
create policy assessment_self_select on public.skill_assessment_results for select to authenticated using ((select auth.uid()) = user_id);
create policy assessment_self_insert on public.skill_assessment_results for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists "notifications: self manage" on public.notifications;
drop policy if exists notifications_self_select on public.notifications;
drop policy if exists notifications_self_update on public.notifications;
create policy notifications_self_select on public.notifications for select to authenticated using ((select auth.uid()) = user_id);
create policy notifications_self_update on public.notifications for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

grant select on public.courses to anon, authenticated;
grant select on public.course_lessons to anon, authenticated;
grant select, update on public.profiles to authenticated;
grant select, insert on public.course_enrollments to authenticated;
grant select, insert, delete on public.lesson_progress to authenticated;
grant select, insert on public.skill_assessment_results to authenticated;
grant select, update on public.notifications to authenticated;
revoke insert, update, delete on public.courses from anon, authenticated;
revoke insert, update, delete on public.course_lessons from anon, authenticated;
revoke insert, delete on public.profiles from anon, authenticated;
revoke update, delete on public.course_enrollments from anon, authenticated;
revoke insert, delete on public.notifications from anon, authenticated;
;

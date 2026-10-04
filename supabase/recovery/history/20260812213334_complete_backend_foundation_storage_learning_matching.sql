-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812213334
-- Mela backend foundation: storage, defaults, learning automation, matching automation, and permission hardening.

-- 1) Secure Storage buckets.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars','avatars',false,5242880,array['image/jpeg','image/png','image/webp']::text[]),
  ('career-documents','career-documents',false,15728640,array['application/pdf','image/jpeg','image/png','application/vnd.openxmlformats-officedocument.wordprocessingml.document']::text[]),
  ('employer-documents','employer-documents',false,20971520,array['application/pdf','image/jpeg','image/png']::text[]),
  ('work-submissions','work-submissions',false,52428800,array['application/pdf','image/jpeg','image/png','image/webp','application/zip','text/plain','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']::text[])
on conflict (id) do update
set public=excluded.public,
    file_size_limit=excluded.file_size_limit,
    allowed_mime_types=excluded.allowed_mime_types;

-- Remove/replace only Mela-owned Storage policies.
drop policy if exists "Mela avatars owner select" on storage.objects;
drop policy if exists "Mela avatars owner insert" on storage.objects;
drop policy if exists "Mela avatars owner update" on storage.objects;
drop policy if exists "Mela avatars owner delete" on storage.objects;
drop policy if exists "Mela career docs select" on storage.objects;
drop policy if exists "Mela career docs insert" on storage.objects;
drop policy if exists "Mela career docs update" on storage.objects;
drop policy if exists "Mela career docs delete" on storage.objects;
drop policy if exists "Mela employer docs select" on storage.objects;
drop policy if exists "Mela employer docs insert" on storage.objects;
drop policy if exists "Mela employer docs update" on storage.objects;
drop policy if exists "Mela employer docs delete" on storage.objects;
drop policy if exists "Mela work submissions select" on storage.objects;
drop policy if exists "Mela work submissions insert" on storage.objects;
drop policy if exists "Mela work submissions update" on storage.objects;
drop policy if exists "Mela work submissions delete" on storage.objects;

create policy "Mela avatars owner select" on storage.objects for select to authenticated
using (bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Mela avatars owner insert" on storage.objects for insert to authenticated
with check (bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Mela avatars owner update" on storage.objects for update to authenticated
using (bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text)
with check (bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Mela avatars owner delete" on storage.objects for delete to authenticated
using (bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);

create policy "Mela career docs select" on storage.objects for select to authenticated
using (
  bucket_id='career-documents' and (
    (storage.foldername(name))[1]=(select auth.uid())::text
    or private.is_admin_user()
    or exists (
      select 1
      from public.applications a
      join public.opportunities o on o.id=a.opportunity_id
      where a.applicant_id::text=(storage.foldername(name))[1]
        and private.has_employer_access(o.employer_id,false)
    )
  )
);
create policy "Mela career docs insert" on storage.objects for insert to authenticated
with check (bucket_id='career-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Mela career docs update" on storage.objects for update to authenticated
using (bucket_id='career-documents' and (storage.foldername(name))[1]=(select auth.uid())::text)
with check (bucket_id='career-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Mela career docs delete" on storage.objects for delete to authenticated
using (bucket_id='career-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);

create policy "Mela employer docs select" on storage.objects for select to authenticated
using (
  bucket_id='employer-documents' and (
    (storage.foldername(name))[1]=(select auth.uid())::text
    or private.is_admin_user()
  )
);
create policy "Mela employer docs insert" on storage.objects for insert to authenticated
with check (bucket_id='employer-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Mela employer docs update" on storage.objects for update to authenticated
using (bucket_id='employer-documents' and (storage.foldername(name))[1]=(select auth.uid())::text)
with check (bucket_id='employer-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Mela employer docs delete" on storage.objects for delete to authenticated
using (bucket_id='employer-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);

create policy "Mela work submissions select" on storage.objects for select to authenticated
using (
  bucket_id='work-submissions' and (
    (storage.foldername(name))[1]=(select auth.uid())::text
    or private.is_admin_user()
    or (
      coalesce((storage.foldername(name))[2],'') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and exists (
        select 1 from public.freelance_contracts c
        where c.id=((storage.foldername(name))[2])::uuid
          and private.has_employer_access(c.employer_id,false)
      )
    )
  )
);
create policy "Mela work submissions insert" on storage.objects for insert to authenticated
with check (bucket_id='work-submissions' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Mela work submissions update" on storage.objects for update to authenticated
using (bucket_id='work-submissions' and (storage.foldername(name))[1]=(select auth.uid())::text)
with check (bucket_id='work-submissions' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Mela work submissions delete" on storage.objects for delete to authenticated
using (bucket_id='work-submissions' and (storage.foldername(name))[1]=(select auth.uid())::text);

-- 2) Notification helpers/defaults.
create or replace function private.create_notification(
  p_user_id uuid,
  p_title text,
  p_body text default null,
  p_ref_table text default null,
  p_ref_id uuid default null
) returns void
language plpgsql security definer set search_path='pg_catalog','public','private'
as $$
begin
  if p_user_id is null then return; end if;
  insert into public.notifications(user_id,title,body,ref_table,ref_id)
  values (p_user_id,p_title,p_body,p_ref_table,p_ref_id);
end;$$;
revoke all on function private.create_notification(uuid,text,text,text,uuid) from public,anon,authenticated;

insert into public.notification_preferences(user_id)
select p.id from public.profiles p
on conflict (user_id) do nothing;

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql security definer set search_path='pg_catalog','public','private'
as $$
begin
  insert into public.profiles (id, full_name, email, preferred_language)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name',''), nullif(split_part(coalesce(new.email,''),'@',1),''), 'Mela User'),
    coalesce(new.email,new.id::text || '@mela.invalid'),
    coalesce(nullif(new.raw_user_meta_data ->> 'preferred_language',''), nullif(new.raw_user_meta_data ->> 'language',''), 'English')
  )
  on conflict (id) do update
  set full_name=excluded.full_name,email=excluded.email,preferred_language=excluded.preferred_language,updated_at=now();

  insert into public.notification_preferences(user_id) values(new.id)
  on conflict (user_id) do nothing;
  return new;
end;$$;
revoke all on function private.handle_new_auth_user() from public,anon,authenticated;

-- Keep notification content immutable to browser users; only read-state is editable.
revoke update on public.notifications from authenticated;
grant update (is_read) on public.notifications to authenticated;
revoke insert,update,delete on public.notifications from anon;

revoke insert,update on public.notification_preferences from authenticated;
grant insert (user_id,email_enabled,push_enabled,sms_enabled,opportunity_alerts,application_updates,mentorship_updates,freelance_updates,marketing_enabled) on public.notification_preferences to authenticated;
grant update (email_enabled,push_enabled,sms_enabled,opportunity_alerts,application_updates,mentorship_updates,freelance_updates,marketing_enabled) on public.notification_preferences to authenticated;

create or replace function private.touch_notification_preferences()
returns trigger language plpgsql set search_path='pg_catalog','public' as $$
begin new.updated_at=now(); return new; end;$$;
drop trigger if exists trg_touch_notification_preferences on public.notification_preferences;
create trigger trg_touch_notification_preferences before update on public.notification_preferences
for each row execute function private.touch_notification_preferences();

-- 3) Harden claimed Career Passport evidence. Students can add evidence but cannot self-verify it.
drop policy if exists "passport: self manage" on public.career_passport_entries;
create policy "Passport evidence owner read" on public.career_passport_entries for select to authenticated
using (user_id=(select auth.uid()) or private.is_admin_user());
create policy "Passport evidence owner create" on public.career_passport_entries for insert to authenticated
with check (user_id=(select auth.uid()) and verified_by is null and verified_at is null);
create policy "Passport evidence owner edit" on public.career_passport_entries for update to authenticated
using (user_id=(select auth.uid()) and verified_at is null)
with check (user_id=(select auth.uid()) and verified_at is null and verified_by is null);
create policy "Passport evidence owner delete unverified" on public.career_passport_entries for delete to authenticated
using (user_id=(select auth.uid()) and verified_at is null);
revoke insert,update on public.career_passport_entries from authenticated;
grant insert (user_id,skill_id,evidence_url) on public.career_passport_entries to authenticated;
grant update (evidence_url) on public.career_passport_entries to authenticated;

-- 4) Learning progress -> module completion -> career badge.
create or replace function private.refresh_profile_badge_count(p_user_id uuid)
returns void language plpgsql security definer set search_path='pg_catalog','public' as $$
begin
  update public.profiles p
  set verified_passport_badge_count=(select count(*)::int from public.user_badges ub where ub.user_id=p_user_id),
      updated_at=now()
  where p.id=p_user_id;
end;$$;
revoke all on function private.refresh_profile_badge_count(uuid) from public,anon,authenticated;

create or replace function private.user_badge_count_trigger()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
begin
  perform private.refresh_profile_badge_count(coalesce(new.user_id,old.user_id));
  return coalesce(new,old);
end;$$;
revoke all on function private.user_badge_count_trigger() from public,anon,authenticated;
drop trigger if exists trg_user_badge_count on public.user_badges;
create trigger trg_user_badge_count after insert or delete on public.user_badges
for each row execute function private.user_badge_count_trigger();

create or replace function private.issue_career_path_badge(p_user_id uuid,p_path_id uuid)
returns void language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare v_badge_id uuid; v_total int; v_done int; v_path_title text;
begin
  select count(*)::int,count(*) filter (where coalesce(smp.completed,false))::int
  into v_total,v_done
  from public.path_modules pm
  left join public.student_module_progress smp on smp.module_id=pm.id and smp.user_id=p_user_id
  where pm.career_path_id=p_path_id;
  if v_total=0 or v_done<v_total then return; end if;

  select b.id,cp.title into v_badge_id,v_path_title
  from public.career_paths cp join public.badges b on b.title=cp.badge_title
  where cp.id=p_path_id;
  if v_badge_id is null then return; end if;

  insert into public.user_badges(user_id,badge_id) values(p_user_id,v_badge_id)
  on conflict do nothing;
  perform private.create_notification(p_user_id,'Career badge earned','You completed the '||v_path_title||' career path.','career_paths',p_path_id);
end;$$;
revoke all on function private.issue_career_path_badge(uuid,uuid) from public,anon,authenticated;

create or replace function private.sync_module_progress_from_lessons()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare v_module uuid; v_path uuid; v_total int; v_done int; v_proctored bool; v_existing_proctored bool;
begin
  select pl.module_id,pm.career_path_id,pm.is_proctored_assessment
  into v_module,v_path,v_proctored
  from public.path_lessons pl join public.path_modules pm on pm.id=pl.module_id
  where pl.id=coalesce(new.lesson_id,old.lesson_id);

  select count(*)::int,count(*) filter (where slp.status='completed')::int
  into v_total,v_done
  from public.path_lessons pl
  left join public.student_lesson_progress slp on slp.lesson_id=pl.id and slp.user_id=coalesce(new.user_id,old.user_id)
  where pl.module_id=v_module and pl.is_published=true;

  select coalesce(proctored_passed,false) into v_existing_proctored
  from public.student_module_progress where user_id=coalesce(new.user_id,old.user_id) and module_id=v_module;

  insert into public.student_module_progress(user_id,module_id,completed)
  values(coalesce(new.user_id,old.user_id),v_module,(v_total>0 and v_done=v_total and (not v_proctored or coalesce(v_existing_proctored,false))))
  on conflict (user_id,module_id) do update
  set completed=(v_total>0 and v_done=v_total and (not v_proctored or coalesce(public.student_module_progress.proctored_passed,false)));

  perform private.issue_career_path_badge(coalesce(new.user_id,old.user_id),v_path);
  return coalesce(new,old);
end;$$;
revoke all on function private.sync_module_progress_from_lessons() from public,anon,authenticated;
drop trigger if exists trg_sync_module_progress_from_lessons on public.student_lesson_progress;
create trigger trg_sync_module_progress_from_lessons
after insert or update of status or delete on public.student_lesson_progress
for each row execute function private.sync_module_progress_from_lessons();

create or replace function private.apply_assessment_to_career_path()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare v_category public.launch_category; v_module uuid; v_path uuid; v_total int; v_done int;
begin
  if new.status<>'graded' or coalesce(new.passed,false)=false or (new.proctored and new.proctor_status<>'clear') then return new; end if;
  select sa.category into v_category from public.skill_assessments sa where sa.id=new.assessment_id;
  select pm.id,pm.career_path_id into v_module,v_path
  from public.path_modules pm join public.career_paths cp on cp.id=pm.career_path_id
  where cp.category=v_category and pm.is_proctored_assessment=true
  order by pm.module_order desc limit 1;
  if v_module is null then return new; end if;

  select count(*)::int,count(*) filter (where slp.status='completed')::int
  into v_total,v_done
  from public.path_lessons pl
  left join public.student_lesson_progress slp on slp.lesson_id=pl.id and slp.user_id=new.user_id
  where pl.module_id=v_module and pl.is_published=true;

  insert into public.student_module_progress(user_id,module_id,completed,quiz_score,proctored_passed,proctored_at)
  values(new.user_id,v_module,(v_total=0 or v_done=v_total),round(new.score)::int,true,coalesce(new.reviewed_at,now()))
  on conflict (user_id,module_id) do update
  set quiz_score=excluded.quiz_score,proctored_passed=true,proctored_at=excluded.proctored_at,
      completed=(v_total=0 or v_done=v_total);

  perform private.issue_career_path_badge(new.user_id,v_path);
  return new;
end;$$;
revoke all on function private.apply_assessment_to_career_path() from public,anon,authenticated;
drop trigger if exists trg_apply_assessment_to_career_path on public.assessment_attempts;
create trigger trg_apply_assessment_to_career_path after update of status,proctor_status on public.assessment_attempts
for each row when (new.status='graded') execute function private.apply_assessment_to_career_path();

-- Browser users must not directly set server-managed module assessment fields.
revoke insert,update on public.student_module_progress from authenticated;
grant insert (user_id,module_id,completed) on public.student_module_progress to authenticated;
grant update (completed) on public.student_module_progress to authenticated;

-- 5) Candidate matching automatically refreshes when applications/skills/configuration change.
create or replace function private.refresh_matches_for_user(p_user_id uuid)
returns void language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare r record;
begin
  for r in select distinct a.opportunity_id from public.applications a where a.applicant_id=p_user_id loop
    perform private.refresh_opportunity_candidate_matches(r.opportunity_id);
  end loop;
end;$$;
revoke all on function private.refresh_matches_for_user(uuid) from public,anon,authenticated;

create or replace function private.match_refresh_on_application()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
begin perform private.refresh_opportunity_candidate_matches(new.opportunity_id); return new; end;$$;
revoke all on function private.match_refresh_on_application() from public,anon,authenticated;
drop trigger if exists trg_match_refresh_on_application on public.applications;
create trigger trg_match_refresh_on_application after insert on public.applications
for each row execute function private.match_refresh_on_application();

create or replace function private.match_refresh_on_skill()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
begin perform private.refresh_matches_for_user(coalesce(new.user_id,old.user_id)); return coalesce(new,old); end;$$;
revoke all on function private.match_refresh_on_skill() from public,anon,authenticated;
drop trigger if exists trg_match_refresh_on_skill on public.verified_skills;
create trigger trg_match_refresh_on_skill after insert or update or delete on public.verified_skills
for each row execute function private.match_refresh_on_skill();

create or replace function private.match_refresh_on_config()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
begin perform private.refresh_opportunity_candidate_matches(new.opportunity_id); return new; end;$$;
revoke all on function private.match_refresh_on_config() from public,anon,authenticated;
drop trigger if exists trg_match_refresh_on_config on public.opportunity_matching_configs;
create trigger trg_match_refresh_on_config after update on public.opportunity_matching_configs
for each row execute function private.match_refresh_on_config();

create or replace function private.match_refresh_on_opportunity()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
begin perform private.refresh_opportunity_candidate_matches(new.id); return new; end;$$;
revoke all on function private.match_refresh_on_opportunity() from public,anon,authenticated;
drop trigger if exists trg_match_refresh_on_opportunity on public.opportunities;
create trigger trg_match_refresh_on_opportunity after update of skills_required,education_level,experience_level,status,verified_active on public.opportunities
for each row execute function private.match_refresh_on_opportunity();

-- Helpful indexes for new cross-table policy/workflow lookups.
create index if not exists applications_applicant_opportunity_idx on public.applications(applicant_id,opportunity_id);
create index if not exists freelance_contracts_employer_id_id_idx on public.freelance_contracts(employer_id,id);
create index if not exists student_lesson_progress_user_status_idx on public.student_lesson_progress(user_id,status);
create index if not exists student_module_progress_user_completed_idx on public.student_module_progress(user_id,completed);

;

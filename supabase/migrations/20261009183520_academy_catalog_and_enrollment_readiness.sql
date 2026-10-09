-- Signed-in course metadata excludes unpublished courses and lesson bodies.
create or replace view admin.course_content_inventory with (security_invoker = true) as
select c.id,c.slug,c.title,c.category,c.level,c.program_type,c.featured_rank,c.is_published,c.price_cents,
 c.duration_minutes,c.prerequisites,c.learning_outcomes,c.audience,c.career_track,
 count(l.id)::int as lesson_count,
 count(l.id) filter(where l.is_preview)::int as preview_lesson_count,
 coalesce(sum(l.duration_minutes),0)::int as lesson_minutes,
 count(l.id)>0 and bool_and(btrim(l.content_text)<>'') as content_available
from public.courses c left join public.course_lessons l on l.course_id=c.id
 group by c.id;
revoke all on admin.course_content_inventory from public,anon,authenticated;
grant select on admin.course_content_inventory to service_role;

create or replace function private.get_mela_academy_catalog() returns jsonb
language sql stable security definer set search_path='' as $fn$
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',c.id,'title',c.title,'description',c.description,'category',c.category,'level',c.level,
  'duration_minutes',c.duration_minutes,'price_cents',c.price_cents,'prerequisites',c.prerequisites,
  'learning_outcomes',c.learning_outcomes,'audience',c.audience,'career_track',c.career_track,
  'lesson_count',i.lesson_count,'preview_lesson_count',i.preview_lesson_count,
  'content_available',coalesce(i.content_available,false)
 ) order by c.featured_rank nulls last,c.title,c.id),'[]'::jsonb)
 from public.courses c join admin.course_content_inventory i on i.id=c.id where c.is_published;
$fn$;
revoke all on function private.get_mela_academy_catalog() from public;
revoke all on function private.get_mela_academy_catalog() from anon;
grant execute on function private.get_mela_academy_catalog() to authenticated,service_role;
create or replace function public.get_mela_academy_catalog() returns jsonb
language sql stable security invoker set search_path='' as $fn$
 select private.get_mela_academy_catalog();
$fn$;
revoke all on function public.get_mela_academy_catalog() from public;
revoke all on function public.get_mela_academy_catalog() from anon;
grant execute on function public.get_mela_academy_catalog() to authenticated,service_role;

create or replace function private.guard_course_enrollment_readiness() returns trigger
language plpgsql security definer set search_path='' as $fn$
begin
 if not exists(select 1 from public.courses c where c.id=new.course_id and c.is_published)
  or not exists(select 1 from public.course_lessons l where l.course_id=new.course_id)
  or exists(select 1 from public.course_lessons l where l.course_id=new.course_id and btrim(l.content_text)='') then
  raise exception 'Course lessons are still being prepared; enrollment is not available yet';
 end if;
 return new;
end;
$fn$;
revoke all on function private.guard_course_enrollment_readiness() from public,anon,authenticated;
drop trigger if exists trg_course_enrollment_readiness on public.course_enrollments;
create trigger trg_course_enrollment_readiness before insert on public.course_enrollments
 for each row execute function private.guard_course_enrollment_readiness();

create or replace function private.enroll_mela_course(p_course_id uuid) returns uuid
language plpgsql security definer set search_path='' as $fn$
declare u uuid:=(select auth.uid()); c public.courses%rowtype;
begin
 if u is null then raise exception 'Authentication required'; end if;
 if not exists(select 1 from public.profiles where id=u and account_status='active' and deleted_at is null) then raise exception 'An active profile is required'; end if;
 select * into c from public.courses where id=p_course_id and is_published for key share;
 if not found then raise exception 'Course is not available'; end if;
 if c.price_cents is distinct from 0 then raise exception 'Paid course enrollment is deferred'; end if;
 if not exists(select 1 from public.course_lessons where course_id=c.id)
  or exists(select 1 from public.course_lessons where course_id=c.id and btrim(content_text)='') then raise exception 'Course lessons are still being prepared'; end if;
 insert into public.course_enrollments(user_id,course_id,progress_pct) values(u,c.id,0)
 on conflict(user_id,course_id) do nothing;
 return c.id;
end;
$fn$;
revoke all on function private.enroll_mela_course(uuid) from public,anon;
grant execute on function private.enroll_mela_course(uuid) to authenticated,service_role;
create or replace function public.enroll_mela_course(p_course_id uuid) returns uuid
language sql security invoker set search_path='' as $fn$ select private.enroll_mela_course(p_course_id); $fn$;
revoke all on function public.enroll_mela_course(uuid) from public,anon;
grant execute on function public.enroll_mela_course(uuid) to authenticated,service_role;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812221936
create or replace function private.enroll_career_path(p_career_path_id uuid)
returns public.career_path_enrollments
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_row public.career_path_enrollments;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_uid and p.role='student'::public.user_role) then raise exception 'student profile required'; end if;
  if not exists(select 1 from public.career_paths cp where cp.id=p_career_path_id) then raise exception 'career path not found'; end if;
  insert into public.career_path_enrollments(user_id,career_path_id)
  values(v_uid,p_career_path_id)
  on conflict(user_id,career_path_id) do update set
    status=case when public.career_path_enrollments.status='paused' then 'in_progress' else public.career_path_enrollments.status end,
    last_activity_at=now(),updated_at=now()
  returning * into v_row;
  perform private.refresh_career_path_enrollment(v_uid,p_career_path_id);
  select * into v_row from public.career_path_enrollments where user_id=v_uid and career_path_id=p_career_path_id;
  return v_row;
end $$;

create or replace function public.enroll_career_path(p_career_path_id uuid)
returns public.career_path_enrollments
language sql security invoker set search_path=''
as $$ select private.enroll_career_path(p_career_path_id); $$;
revoke all on function private.enroll_career_path(uuid) from public,anon;
grant execute on function private.enroll_career_path(uuid) to authenticated,service_role;
revoke all on function public.enroll_career_path(uuid) from public,anon;
grant execute on function public.enroll_career_path(uuid) to authenticated,service_role;
;

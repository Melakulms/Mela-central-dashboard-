alter table public.teacher_profiles add column if not exists verification_notes text;
grant select(verification_notes) on public.teacher_profiles to authenticated;

create table if not exists private.educator_review_authorizations (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  subject_areas text[] not null check (cardinality(subject_areas) > 0),
  active boolean not null default true,
  granted_by uuid not null references public.profiles(id) on delete restrict,
  grant_note text not null check (char_length(btrim(grant_note)) between 5 and 4000),
  granted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table private.educator_review_authorizations enable row level security;
revoke all on table private.educator_review_authorizations from public, anon, authenticated;
create index if not exists educator_review_authorizations_active_idx on private.educator_review_authorizations(active, user_id);

create or replace function private.question_reviewer_allowed_v18(p_uid uuid, p_program_key text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select (
    p_uid = (select auth.uid()) and private.is_admin_user()
  ) or exists(
    select 1
    from public.teacher_profiles t
    join public.mela_learning_programs lp on lp.program_key=p_program_key
    where t.user_id=p_uid and t.verification_status='approved'
      and (lp.subject_key=any(coalesce(t.subjects_taught,'{}'::text[])) or lp.subject_title=any(coalesce(t.subjects_taught,'{}'::text[])))
      and (
        exists(
          select 1 from private.educator_review_authorizations a
          where a.user_id=p_uid and a.active and (lp.subject_key=any(a.subject_areas) or lp.subject_title=any(a.subject_areas))
        )
        or exists(
          select 1 from public.educator_profiles e
          where e.user_id=p_uid and e.verified and e.active and (lp.subject_key=any(coalesce(e.subject_areas,'{}'::text[])) or lp.subject_title=any(coalesce(e.subject_areas,'{}'::text[])))
        )
      )
  );
$function$;

create or replace function private.can_review_questions_v18()
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then return false; end if;
  if private.is_admin_user() then return true; end if;
  return exists(select 1 from public.mela_learning_programs lp where private.question_reviewer_allowed_v18(v_uid,lp.program_key));
end;
$function$;

create or replace function private.get_teacher_verification_queue(p_status text default 'pending', p_limit integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare v_limit integer := least(greatest(coalesce(p_limit,100),1),200);
begin
  if not private.is_admin_user() then raise exception 'admin authorization with MFA required' using errcode='42501'; end if;
  if p_status is not null and p_status not in ('pending','approved','rejected','suspended') then raise exception 'invalid teacher verification status'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'user_id',t.user_id,'full_name',p.full_name,'email',p.email,'account_status',p.account_status,
      'qualification',t.qualification,'subjects_taught',t.subjects_taught,'grade_levels',t.grade_levels,
      'teaching_experience_years',t.teaching_experience_years,'institution',t.institution,'certifications',t.certifications,
      'biography',t.biography,'verification_status',t.verification_status,'verification_notes',t.verification_notes,
      'verified_by',t.verified_by,'verified_at',t.verified_at,'review_authorized',coalesce(a.active,false),
      'review_subject_areas',a.subject_areas,'created_at',t.created_at,'updated_at',t.updated_at
    ) order by t.created_at asc)
    from (select * from public.teacher_profiles t0 where (p_status is null or t0.verification_status=p_status) order by t0.created_at asc limit v_limit) t
    join public.profiles p on p.id=t.user_id
    left join private.educator_review_authorizations a on a.user_id=t.user_id
  ),'[]'::jsonb);
end;
$function$;

create or replace function private.review_teacher_profile(p_user_id uuid, p_decision text, p_note text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_note text := btrim(coalesce(p_note,''));
  v_before public.teacher_profiles%rowtype;
  v_after public.teacher_profiles%rowtype;
begin
  if not private.is_admin_user() or v_actor is null then raise exception 'admin authorization with MFA required' using errcode='42501'; end if;
  if p_decision not in ('approved','rejected','suspended') then raise exception 'invalid teacher verification decision'; end if;
  if char_length(v_note)<5 or char_length(v_note)>4000 then raise exception 'verification note must be 5-4000 characters'; end if;

  select * into v_before from public.teacher_profiles where user_id=p_user_id for update;
  if not found then raise exception 'teacher profile not found'; end if;
  if p_decision='approved' then
    if coalesce(char_length(btrim(v_before.qualification)),0)<2 then raise exception 'qualification is required before approval'; end if;
    if coalesce(cardinality(v_before.subjects_taught),0)=0 then raise exception 'at least one teaching subject is required before approval'; end if;
    if coalesce(cardinality(v_before.grade_levels),0)=0 then raise exception 'at least one grade level is required before approval'; end if;
    if coalesce(char_length(btrim(v_before.institution)),0)<2 then raise exception 'institution is required before approval'; end if;
  end if;

  update public.teacher_profiles
  set verification_status=p_decision,verification_notes=v_note,verified_by=v_actor,
      verified_at=case when p_decision='approved' then now() else null end,updated_at=now()
  where user_id=p_user_id returning * into v_after;

  if p_decision='approved' then
    insert into private.educator_review_authorizations(user_id,subject_areas,active,granted_by,grant_note,granted_at,updated_at)
    values(p_user_id,v_after.subjects_taught,true,v_actor,v_note,now(),now())
    on conflict(user_id) do update set subject_areas=excluded.subject_areas,active=true,granted_by=excluded.granted_by,grant_note=excluded.grant_note,granted_at=now(),updated_at=now();
  else
    update private.educator_review_authorizations set active=false,updated_at=now(),granted_by=v_actor,grant_note=v_note where user_id=p_user_id;
    update public.educator_profiles set active=false,updated_at=now() where user_id=p_user_id;
  end if;

  insert into admin.audit_log(actor_user_id,actor_role,action,target_schema,target_table,target_id,before_data,after_data,metadata)
  values(v_actor,'admin','teacher.verification.review','public','teacher_profiles',p_user_id::text,to_jsonb(v_before),to_jsonb(v_after),jsonb_build_object('decision',p_decision,'review_authorization_active',p_decision='approved'));

  return jsonb_build_object('user_id',p_user_id,'verification_status',p_decision,'review_authorized',p_decision='approved','subject_areas',v_after.subjects_taught,'verified_at',v_after.verified_at);
end;
$function$;

revoke all on function private.get_teacher_verification_queue(text,integer) from public,anon;
revoke all on function private.review_teacher_profile(uuid,text,text) from public,anon;
grant execute on function private.get_teacher_verification_queue(text,integer) to authenticated,service_role;
grant execute on function private.review_teacher_profile(uuid,text,text) to authenticated,service_role;

create or replace function public.get_teacher_verification_queue(p_status text default 'pending',p_limit integer default 100)
returns jsonb language sql stable security invoker set search_path to '' as $function$
select private.get_teacher_verification_queue(p_status,p_limit);
$function$;
create or replace function public.review_teacher_profile(p_user_id uuid,p_decision text,p_note text)
returns jsonb language sql security invoker set search_path to '' as $function$
select private.review_teacher_profile(p_user_id,p_decision,p_note);
$function$;
revoke all on function public.get_teacher_verification_queue(text,integer) from public,anon;
revoke all on function public.review_teacher_profile(uuid,text,text) from public,anon;
grant execute on function public.get_teacher_verification_queue(text,integer) to authenticated,service_role;
grant execute on function public.review_teacher_profile(uuid,text,text) to authenticated,service_role;

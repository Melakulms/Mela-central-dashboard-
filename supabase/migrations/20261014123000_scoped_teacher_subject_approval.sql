-- Only explicit, certificate-verified subject subsets are authorized for educator review.
-- Legacy three-argument teacher approval is deliberately refused; existing rejection
-- and suspension continue to use it safely.
CREATE OR REPLACE FUNCTION private.review_teacher_profile(p_user_id uuid, p_decision text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    raise exception 'Use subject-scoped credential-based teacher approval'; 
    if not exists(select 1 from public.teacher_credential_documents d
      where d.teacher_id=p_user_id and d.review_status='approved') then
      raise exception 'approve at least one independently verified qualification document before approving teacher';
    end if;
    if coalesce(char_length(btrim(v_before.qualification)),0)<2 then raise exception 'qualification is required before approval'; end if;
    if coalesce(cardinality(v_before.subjects_taught),0)=0 then raise exception 'at least one teaching subject is required before approval'; end if;
    if coalesce(cardinality(v_before.grade_levels),0)=0 then raise exception 'at least one grade level is required before approval'; end if;
    if coalesce(char_length(btrim(v_before.institution)),0)<2 then raise exception 'institution is required before approval'; end if;
  end if;

  update public.teacher_profiles
  set verification_status=p_decision,
      verification_notes=v_note,
      verified_by=v_actor,
      verified_at=case when p_decision='approved' then now() else null end,
      updated_at=now()
  where user_id=p_user_id
  returning * into v_after;

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
CREATE OR REPLACE FUNCTION private.review_teacher_profile_scoped(p_user_id uuid, p_decision text, p_note text, p_subjects text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    if coalesce(cardinality(p_subjects),0)=0 then
      raise exception 'Select at least one independently verified teaching subject';
    end if;
    if exists (
      select 1 from unnest(p_subjects) chosen(s)
      where chosen.s is null or char_length(btrim(chosen.s))=0 or
        not exists(select 1 from unnest(v_before.subjects_taught) stated(x)
          where lower(btrim(stated.x))=lower(btrim(chosen.s)))
    ) then raise exception 'Only submitted teaching subjects may be authorized'; end if;
    if not exists(select 1 from public.teacher_credential_documents d
      where d.teacher_id=p_user_id and d.review_status='approved') then
      raise exception 'approve at least one independently verified qualification document before approving teacher';
    end if;
    if coalesce(char_length(btrim(v_before.qualification)),0)<2 then raise exception 'qualification is required before approval'; end if;
    if coalesce(cardinality(v_before.subjects_taught),0)=0 then raise exception 'at least one teaching subject is required before approval'; end if;
    if coalesce(cardinality(v_before.grade_levels),0)=0 then raise exception 'at least one grade level is required before approval'; end if;
    if coalesce(char_length(btrim(v_before.institution)),0)<2 then raise exception 'institution is required before approval'; end if;
  end if;

  update public.teacher_profiles
  set verification_status=p_decision,
      verification_notes=v_note,
      verified_by=v_actor,
      verified_at=case when p_decision='approved' then now() else null end,
      updated_at=now()
  where user_id=p_user_id
  returning * into v_after;

  if p_decision='approved' then
    insert into private.educator_review_authorizations(user_id,subject_areas,active,granted_by,grant_note,granted_at,updated_at)
    values(p_user_id,p_subjects,true,v_actor,v_note,now(),now())
    on conflict(user_id) do update set subject_areas=excluded.subject_areas,active=true,granted_by=excluded.granted_by,grant_note=excluded.grant_note,granted_at=now(),updated_at=now();
  else
    update private.educator_review_authorizations set active=false,updated_at=now(),granted_by=v_actor,grant_note=v_note where user_id=p_user_id;
    update public.educator_profiles set active=false,updated_at=now() where user_id=p_user_id;
  end if;

  insert into admin.audit_log(actor_user_id,actor_role,action,target_schema,target_table,target_id,before_data,after_data,metadata)
  values(v_actor,'admin','teacher.verification.review','public','teacher_profiles',p_user_id::text,to_jsonb(v_before),to_jsonb(v_after),jsonb_build_object('decision',p_decision,'review_authorization_active',p_decision='approved','authorized_subjects',p_subjects));

  return jsonb_build_object('user_id',p_user_id,'verification_status',p_decision,'review_authorized',p_decision='approved','subject_areas',p_subjects,'verified_at',v_after.verified_at);
end;
$function$;
create or replace function public.review_teacher_profile_scoped(
 p_user_id uuid, p_decision text, p_note text, p_subjects text[])
returns jsonb language sql set search_path to ''
as $function$
 select private.review_teacher_profile_scoped(p_user_id,p_decision,p_note,p_subjects);
$function$;
revoke all on function public.review_teacher_profile_scoped(uuid,text,text,text[]) from PUBLIC,anon;
grant execute on function public.review_teacher_profile_scoped(uuid,text,text,text[]) to authenticated;

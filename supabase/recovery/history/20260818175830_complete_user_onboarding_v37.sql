-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260818175830
create or replace function public.complete_my_profile_v37(
  p_full_name text,
  p_preferred_language text default 'en',
  p_city text default null,
  p_region text default null,
  p_institution_name text default null,
  p_details jsonb default '{}'::jsonb
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_profile public.profiles%rowtype;
  v_lang text := lower(coalesce(nullif(btrim(p_preferred_language),''),'en'));
  v_company_name text;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select * into v_profile from public.profiles where id=v_uid for update;
  if not found then raise exception 'profile not found'; end if;
  if v_profile.account_status <> 'active' or not (v_profile.email_verified or v_profile.phone_verified) then
    raise exception 'verified active account required';
  end if;
  if v_profile.role_selected_at is null or v_profile.role not in ('student'::public.user_role,'parent'::public.user_role,'teacher'::public.user_role,'company'::public.user_role) then
    raise exception 'account type selection is required';
  end if;
  if length(btrim(coalesce(p_full_name,''))) < 2 then raise exception 'full name is required'; end if;
  if v_lang = 'or' then v_lang := 'om'; end if;
  if not exists(select 1 from public.platform_languages l where l.language_code=v_lang and l.enabled) then
    raise exception 'unsupported language';
  end if;

  if v_profile.role='student'::public.user_role and v_profile.education_stage_key is null then
    raise exception 'education stage is required for student accounts';
  end if;

  update public.profiles
     set full_name=btrim(p_full_name),
         preferred_language=v_lang,
         city=coalesce(nullif(btrim(p_city),''),city),
         region=coalesce(nullif(btrim(p_region),''),region),
         institution_name=coalesce(nullif(btrim(p_institution_name),''),institution_name),
         profile_completion=100,
         onboarding_step='complete',
         education_onboarding_completed=case when role='student'::public.user_role then true else education_onboarding_completed end,
         updated_at=now()
   where id=v_uid
   returning * into v_profile;

  if v_profile.role='student'::public.user_role then
    insert into public.student_profiles(user_id,school_name,city,region,subjects,learning_interests,skills,goals,preferred_learning_areas)
    values(
      v_uid,
      nullif(btrim(p_institution_name),''),
      nullif(btrim(p_city),''),
      nullif(btrim(p_region),''),
      array(select jsonb_array_elements_text(coalesce(p_details->'subjects','[]'::jsonb))),
      array(select jsonb_array_elements_text(coalesce(p_details->'learning_interests','[]'::jsonb))),
      array(select jsonb_array_elements_text(coalesce(p_details->'skills','[]'::jsonb))),
      array(select jsonb_array_elements_text(coalesce(p_details->'goals','[]'::jsonb))),
      array(select jsonb_array_elements_text(coalesce(p_details->'preferred_learning_areas','[]'::jsonb)))
    )
    on conflict(user_id) do update set
      school_name=coalesce(excluded.school_name,public.student_profiles.school_name),
      city=coalesce(excluded.city,public.student_profiles.city),
      region=coalesce(excluded.region,public.student_profiles.region),
      subjects=case when cardinality(excluded.subjects)>0 then excluded.subjects else public.student_profiles.subjects end,
      learning_interests=case when cardinality(excluded.learning_interests)>0 then excluded.learning_interests else public.student_profiles.learning_interests end,
      skills=case when cardinality(excluded.skills)>0 then excluded.skills else public.student_profiles.skills end,
      goals=case when cardinality(excluded.goals)>0 then excluded.goals else public.student_profiles.goals end,
      preferred_learning_areas=case when cardinality(excluded.preferred_learning_areas)>0 then excluded.preferred_learning_areas else public.student_profiles.preferred_learning_areas end,
      updated_at=now();
  elsif v_profile.role='parent'::public.user_role then
    insert into public.parent_profiles(user_id,occupation,city,region,interests,skills,employment_preferences)
    values(
      v_uid,
      nullif(btrim(p_details->>'occupation'),''),
      nullif(btrim(p_city),''),
      nullif(btrim(p_region),''),
      array(select jsonb_array_elements_text(coalesce(p_details->'interests','[]'::jsonb))),
      array(select jsonb_array_elements_text(coalesce(p_details->'skills','[]'::jsonb))),
      array(select jsonb_array_elements_text(coalesce(p_details->'employment_preferences','[]'::jsonb)))
    )
    on conflict(user_id) do update set
      occupation=coalesce(excluded.occupation,public.parent_profiles.occupation),
      city=coalesce(excluded.city,public.parent_profiles.city),
      region=coalesce(excluded.region,public.parent_profiles.region),
      interests=case when cardinality(excluded.interests)>0 then excluded.interests else public.parent_profiles.interests end,
      skills=case when cardinality(excluded.skills)>0 then excluded.skills else public.parent_profiles.skills end,
      employment_preferences=case when cardinality(excluded.employment_preferences)>0 then excluded.employment_preferences else public.parent_profiles.employment_preferences end,
      updated_at=now();
  elsif v_profile.role='teacher'::public.user_role then
    insert into public.teacher_profiles(user_id,qualification,subjects_taught,grade_levels,teaching_experience_years,institution,skills,certifications,biography,teaching_interests)
    values(
      v_uid,
      nullif(btrim(p_details->>'qualification'),''),
      array(select jsonb_array_elements_text(coalesce(p_details->'subjects_taught','[]'::jsonb))),
      array(select jsonb_array_elements_text(coalesce(p_details->'grade_levels','[]'::jsonb))),
      greatest(0,coalesce(nullif(p_details->>'teaching_experience_years','')::integer,0)),
      nullif(btrim(p_institution_name),''),
      array(select jsonb_array_elements_text(coalesce(p_details->'skills','[]'::jsonb))),
      array(select jsonb_array_elements_text(coalesce(p_details->'certifications','[]'::jsonb))),
      nullif(btrim(p_details->>'biography'),''),
      array(select jsonb_array_elements_text(coalesce(p_details->'teaching_interests','[]'::jsonb)))
    )
    on conflict(user_id) do update set
      qualification=coalesce(excluded.qualification,public.teacher_profiles.qualification),
      subjects_taught=case when cardinality(excluded.subjects_taught)>0 then excluded.subjects_taught else public.teacher_profiles.subjects_taught end,
      grade_levels=case when cardinality(excluded.grade_levels)>0 then excluded.grade_levels else public.teacher_profiles.grade_levels end,
      teaching_experience_years=excluded.teaching_experience_years,
      institution=coalesce(excluded.institution,public.teacher_profiles.institution),
      skills=case when cardinality(excluded.skills)>0 then excluded.skills else public.teacher_profiles.skills end,
      certifications=case when cardinality(excluded.certifications)>0 then excluded.certifications else public.teacher_profiles.certifications end,
      biography=coalesce(excluded.biography,public.teacher_profiles.biography),
      teaching_interests=case when cardinality(excluded.teaching_interests)>0 then excluded.teaching_interests else public.teacher_profiles.teaching_interests end,
      updated_at=now();
  elsif v_profile.role='company'::public.user_role then
    v_company_name := coalesce(nullif(btrim(p_details->>'company_name'),''),nullif(btrim(p_institution_name),''));
    if v_company_name is null then raise exception 'company name is required'; end if;

    insert into public.company_profiles(user_id,authorized_representative,representative_title,business_registration_number)
    values(v_uid,btrim(p_full_name),nullif(btrim(p_details->>'representative_title'),''),nullif(btrim(p_details->>'business_registration_number'),''))
    on conflict(user_id) do update set
      authorized_representative=excluded.authorized_representative,
      representative_title=coalesce(excluded.representative_title,public.company_profiles.representative_title),
      business_registration_number=coalesce(excluded.business_registration_number,public.company_profiles.business_registration_number),
      updated_at=now();

    if not exists(select 1 from public.employer_registration_requests r where r.applicant_user_id=v_uid and r.status in ('pending','under_review')) then
      insert into public.employer_registration_requests(applicant_user_id,company_name,legal_name,registration_number,industry,website,contact_email,phone_number,headquarters,description,status)
      values(
        v_uid,
        v_company_name,
        nullif(btrim(p_details->>'legal_name'),''),
        nullif(btrim(p_details->>'business_registration_number'),''),
        nullif(btrim(p_details->>'industry'),''),
        nullif(btrim(p_details->>'website'),''),
        v_profile.email,
        coalesce(v_profile.phone_number,v_profile.contact_phone),
        coalesce(nullif(btrim(p_city),''),nullif(btrim(p_region),'')),
        nullif(btrim(p_details->>'description'),''),
        'pending'
      );
    end if;
  end if;

  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
  values(v_uid,'complete_profile_v37','profile',v_uid,jsonb_build_object('role',v_profile.role,'language',v_lang,'profile_completion',100));

  return v_profile;
end;
$$;

revoke all on function public.complete_my_profile_v37(text,text,text,text,text,jsonb) from public;
grant execute on function public.complete_my_profile_v37(text,text,text,text,text,jsonb) to authenticated;

comment on function public.complete_my_profile_v37(text,text,text,text,text,jsonb) is 'Completes the verified user onboarding flow and safely writes role-specific profile data. Role selection remains controlled by select_account_type_v35.';
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825163904
begin;
grant update (date_of_birth,gender,school_name,city,region,subjects,learning_interests,skills,goals,preferred_learning_areas) on public.student_profiles to authenticated;
grant update (qualification,subjects_taught,grade_levels,teaching_experience_years,institution,skills,certifications,biography,teaching_interests,availability) on public.teacher_profiles to authenticated;
grant update (occupation,city,region,interests,skills,employment_preferences) on public.parent_profiles to authenticated;
grant update (authorized_representative,representative_title,business_registration_number) on public.company_profiles to authenticated;
grant update (headline,expertise,organization,years_experience,bio,languages) on public.mentor_profiles to authenticated;
grant update (role_title,subject_areas,stage_keys) on public.educator_profiles to authenticated;
commit;
;

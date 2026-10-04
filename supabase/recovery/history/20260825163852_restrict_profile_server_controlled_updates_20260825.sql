-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825163852
begin;
revoke update on table public.profiles from authenticated;
revoke update on table public.student_profiles from authenticated;
revoke update on table public.teacher_profiles from authenticated;
revoke update on table public.parent_profiles from authenticated;
revoke update on table public.company_profiles from authenticated;
revoke update on table public.mentor_profiles from authenticated;
revoke update on table public.educator_profiles from authenticated;
grant update (full_name,school_name,region,avatar_url,email,phone_number,university,major,graduation_year,gpa,preferred_language,bio,city,availability_status,portfolio_url,linkedin_url,github_url,contact_phone,education_stage_key,grade_level,institution_name,onboarding_step) on table public.profiles to authenticated;
commit;
;

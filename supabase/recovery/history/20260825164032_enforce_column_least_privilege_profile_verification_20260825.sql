-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825164032
revoke insert on company_profiles from authenticated;
grant insert (user_id, authorized_representative, representative_title, business_registration_number) on company_profiles to authenticated;
revoke insert on teacher_profiles from authenticated;
grant insert (user_id, qualification, subjects_taught, grade_levels, teaching_experience_years, institution, skills, certifications, biography, teaching_interests, availability) on teacher_profiles to authenticated;
revoke insert on educator_profiles from authenticated;
grant insert (user_id, partner_organization_id, role_title, subject_areas, stage_keys) on educator_profiles to authenticated;
revoke insert on mentor_profiles from authenticated;
grant insert (user_id, headline, expertise, organization, years_experience, bio, languages) on mentor_profiles to authenticated;
revoke insert on payout_accounts from authenticated;
grant insert (user_id, account_name, account_number, bank_code, bank_name, currency) on payout_accounts to authenticated;
revoke update on sector_partner_organizations from authenticated;

;

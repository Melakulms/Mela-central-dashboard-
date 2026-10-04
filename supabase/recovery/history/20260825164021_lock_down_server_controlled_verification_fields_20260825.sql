-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825164021
revoke insert (verification_status, verified_by, verified_at) on company_profiles from authenticated;
revoke insert (verification_status, verified_by, verified_at) on teacher_profiles from authenticated;
revoke insert (verified, verified_by, verified_at, active) on educator_profiles from authenticated;
revoke insert (verified, verified_by, verified_at, active) on mentor_profiles from authenticated;
revoke insert (active) on payout_accounts from authenticated;
revoke update (verification_status, verified_by, verified_at) on sector_partner_organizations from authenticated;

;

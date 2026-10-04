-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260923101031

-- Confirmed by direct reproduction: posting an opportunity as a real employer
-- fails with "permission denied for function is_admin_user" even after fixing
-- has_employer_access. Some trigger/policy in this path calls it in a context
-- that does not inherit elevated privilege the way the profiles guard triggers
-- do. Same safe reasoning as the other grants: SECURITY DEFINER, logic
-- unchanged, this only allows authenticated to invoke it.
GRANT EXECUTE ON FUNCTION private.is_admin_user() TO authenticated;

;

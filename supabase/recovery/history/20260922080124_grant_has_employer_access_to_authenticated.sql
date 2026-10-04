-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260922080124

-- private.has_employer_access(p_employer_id, p_write) is SECURITY DEFINER and
-- used inside the opportunities INSERT RLS policy (and likely others), but had
-- no EXECUTE grant for `authenticated`. Since RLS policies evaluate as the
-- querying role, this meant NO real employer could ever post an opportunity --
-- confirmed by reproduction: "permission denied for function has_employer_access"
-- when attempting the exact insert a real employer would make.
GRANT EXECUTE ON FUNCTION private.has_employer_access(uuid, boolean) TO authenticated;

;

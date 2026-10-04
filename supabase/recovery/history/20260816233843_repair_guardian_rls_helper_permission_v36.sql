-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260816233843
grant execute on function private.has_verified_guardian_link(uuid,uuid) to authenticated,service_role;
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826132841
REVOKE EXECUTE ON FUNCTION private.submit_task_milestone(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION private.submit_task_milestone(uuid, text, text) FROM PUBLIC, anon, authenticated;
;

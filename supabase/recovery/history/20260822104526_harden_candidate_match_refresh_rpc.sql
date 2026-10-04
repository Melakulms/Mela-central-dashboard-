-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822104526
revoke execute on function public.refresh_candidate_matches(uuid) from authenticated; revoke execute on function private.refresh_opportunity_candidate_matches(uuid) from authenticated;
;

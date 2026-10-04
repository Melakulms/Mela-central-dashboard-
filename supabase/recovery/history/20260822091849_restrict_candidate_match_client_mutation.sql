-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822091849
revoke insert,delete on public.candidate_matches from authenticated;
;

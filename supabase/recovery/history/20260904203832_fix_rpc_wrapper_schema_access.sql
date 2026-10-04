-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260904203832

-- These wrapper functions call into the `private` schema, which `authenticated`
-- has no USAGE on. Without SECURITY DEFINER they run as the calling role and
-- fail with "permission denied for schema private" for every real user call.
-- The actual authorization logic already lives inside each private.* implementation
-- (auth.uid() checks, ownership checks, status-transition checks), so making the
-- pass-through wrapper SECURITY DEFINER does not change what's allowed -- it only
-- lets the call reach those checks.

ALTER FUNCTION public.complete_mentorship_session(uuid, text) SECURITY DEFINER;
ALTER FUNCTION public.cancel_mentorship_session(uuid, text) SECURITY DEFINER;
ALTER FUNCTION public.schedule_mentorship_session(uuid, timestamptz, integer, text) SECURITY DEFINER;
ALTER FUNCTION public.respond_mentorship_request(uuid, text) SECURITY DEFINER;
ALTER FUNCTION public.cancel_mentorship_request(uuid) SECURITY DEFINER;

ALTER FUNCTION public.award_freelance_task(uuid, numeric, text) SECURITY DEFINER;
ALTER FUNCTION public.respond_freelance_contract(uuid, boolean, text) SECURITY DEFINER;
ALTER FUNCTION public.create_task_milestone(uuid, text, numeric, timestamptz, text) SECURITY DEFINER;
ALTER FUNCTION public.submit_task_milestone(uuid) SECURITY DEFINER;
ALTER FUNCTION public.submit_task_milestone(uuid, text, text) SECURITY DEFINER;
ALTER FUNCTION public.review_task_milestone(uuid, text, text) SECURITY DEFINER;
ALTER FUNCTION public.shortlist_freelance_proposal(uuid) SECURITY DEFINER;
ALTER FUNCTION public.withdraw_freelance_proposal(uuid) SECURITY DEFINER;
ALTER FUNCTION public.cancel_freelance_contract(uuid, text) SECURITY DEFINER;

-- review_task_milestone's wrapper had EXECUTE revoked from authenticated entirely
-- (a real employer/admin needs to call this) -- restore it now that the function works.
GRANT EXECUTE ON FUNCTION public.review_task_milestone(uuid, text, text) TO authenticated;

;

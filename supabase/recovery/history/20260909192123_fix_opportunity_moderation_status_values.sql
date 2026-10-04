-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260909192123

-- Two related mismatches found: (1) the moderation_status CHECK constraint
-- allows pending_review/approved/rejected/suspended/archived, but the
-- enforce_opportunity_review_transition trigger's own transition table
-- references 'flagged' as a real state (both as a source and destination),
-- and mela-admin-api's opportunity.review action allows an admin to choose
-- 'flagged' or 'pending' as target values. 'flagged' was simply missing from
-- the constraint (confirmed: flagging any approved opportunity via the real
-- admin action would fail). (2) the edge function accepts 'pending' as a
-- valid target but the actual canonical value used everywhere else (inserts,
-- the trigger) is 'pending_review' -- fixing the constraint alone would still
-- leave 'pending' from the API able to violate it, so the function needs to
-- match the DB's real vocabulary.

ALTER TABLE public.opportunities DROP CONSTRAINT opportunities_moderation_status_check;
ALTER TABLE public.opportunities ADD CONSTRAINT opportunities_moderation_status_check
  CHECK (moderation_status = ANY (ARRAY['pending_review'::text, 'flagged'::text, 'approved'::text, 'rejected'::text, 'suspended'::text, 'archived'::text]));

;

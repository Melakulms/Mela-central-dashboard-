-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260921204443

-- The other AI working on this repo added a one-time migration to close
-- expired-by-deadline opportunities (status='open' but deadline has passed).
-- That's correct but one-time; nothing was keeping it correct going forward.
-- Wrapping it in a function and scheduling it daily, matching the existing
-- maintenance job pattern (mela-opportunity-reminders, mela-external-source-freshness).

CREATE OR REPLACE FUNCTION private.close_expired_opportunities()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.opportunities
  SET status='closed', updated_at=now()
  WHERE status='open' AND deadline < current_date;
$$;

SELECT cron.schedule('mela-close-expired-opportunities', '30 2 * * *', 'select private.close_expired_opportunities();');

-- Run it once now too, so currently-expired rows are fixed immediately rather than waiting for 2:30am.
SELECT private.close_expired_opportunities();

;

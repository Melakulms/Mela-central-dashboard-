-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825202027
CREATE UNIQUE INDEX IF NOT EXISTS earnings_ledger_referral_registration_uidx ON public.earnings_ledger (user_id, source_id) WHERE source_type = 'referral_reward';
;

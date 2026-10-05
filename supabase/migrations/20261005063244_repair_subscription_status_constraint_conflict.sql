set lock_timeout='5s';
-- The payment finalizer, access checks, expiry job and current-row unique index
-- all use the original premium_* status vocabulary. Keep that check intact.
-- A later incompatible check reduced valid statuses to free/cancelled only.
alter table public.user_subscriptions drop constraint user_subscriptions_status_valid;

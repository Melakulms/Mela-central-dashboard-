set lock_timeout='5s';
-- A timed-out initialization must be reconciled, not replaced with another charge.
create unique index payments_one_open_checkout_uidx on public.payments(user_id,course_id,mode) where status in ('initiated','pending');
create unique index learning_one_open_checkout_uidx on public.mela_learning_payment_attempts(user_id,product_key,mode) where status in ('initiated','pending');
create unique index escrow_one_open_checkout_uidx on public.escrow_payment_attempts(escrow_id,mode) where status in ('initiated','pending');

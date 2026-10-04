-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260920110835

drop view if exists public.my_payment_history;
create view public.my_payment_history
with (security_invoker=true)
as
select p.id,
       p.course_id,
       c.slug as course_slug,
       c.title as course_title,
       p.tx_ref,
       p.expected_amount_cents,
       p.expected_currency,
       p.status,
       p.provider_status,
       p.provider_method,
       p.created_at,
       p.paid_at
from public.payments p
join public.courses c on c.id=p.course_id
where p.user_id=(select auth.uid());

revoke all on public.my_payment_history from anon;
grant select on public.my_payment_history to authenticated;

;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813104010
drop policy if exists mela_gate_payouts on public.escrow_transactions;
drop policy if exists mela_gate_earn_work on public.escrow_transactions;
create policy mela_gate_earn_work on public.escrow_transactions
as restrictive
for all
to anon,authenticated
using (public.platform_feature_available('earn_work'))
with check (public.platform_feature_available('earn_work'));
;

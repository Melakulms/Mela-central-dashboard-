-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260827145135
drop policy if exists "Payout account owner delete" on public.payout_accounts;
create policy "Payout account owner delete"
on public.payout_accounts
for delete
to authenticated
using (
  user_id = (select auth.uid())
  and active = false
);
;

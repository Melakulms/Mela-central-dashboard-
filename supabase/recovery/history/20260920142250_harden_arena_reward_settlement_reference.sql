-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260920142250
create unique index if not exists arena_rewards_external_ref_uq on public.arena_rewards(external_ref) where external_ref is not null;
alter table public.arena_rewards
  drop constraint if exists arena_rewards_cash_amount_chk;
alter table public.arena_rewards
  add constraint arena_rewards_cash_amount_chk
  check (reward_type <> 'cash' or (cash_amount is not null and cash_amount > 0));
;

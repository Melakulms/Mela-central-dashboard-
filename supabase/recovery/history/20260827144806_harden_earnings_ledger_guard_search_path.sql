-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260827144806
create or replace function public.guard_earnings_ledger_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.user_id is distinct from old.user_id
       or new.source_type is distinct from old.source_type
       or new.source_id is distinct from old.source_id
       or new.gross_amount is distinct from old.gross_amount
       or new.platform_fee is distinct from old.platform_fee
       or new.net_amount is distinct from old.net_amount
       or new.currency is distinct from old.currency then
      if not public.is_admin_user((select auth.uid())) then
        raise exception 'Earnings ledger identity and financial fields are immutable for non-admin users';
      end if;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.guard_earnings_ledger_mutation() from public;
revoke all on function public.guard_earnings_ledger_mutation() from anon;
revoke all on function public.guard_earnings_ledger_mutation() from authenticated;

;

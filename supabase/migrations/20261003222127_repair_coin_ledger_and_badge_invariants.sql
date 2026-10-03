set lock_timeout = '5s';
-- Abort rather than reinterpret any incompatible legacy balances or ledger rows.
alter table public.coin_transactions alter column user_id set not null;
alter table public.coin_transactions alter column amount set not null;
alter table public.coin_transactions add constraint coin_amount_nonzero check (amount <> 0);
alter table public.profiles add constraint profile_coin_balance_nonnegative check (coin_balance >= 0);

create or replace function public.fn_apply_coin_transaction()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.profiles
    set coin_balance = (coalesce(coin_balance,0)::bigint + new.amount)::integer, updated_at = now()
    where id = new.user_id
      and coalesce(coin_balance,0)::bigint + new.amount between 0 and 2147483647;
  if not found then
    raise exception 'Coin transaction would overdraw or overflow the balance, or the account is unavailable'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke all on function public.fn_apply_coin_transaction() from public,anon,authenticated;

create or replace function private.reject_coin_ledger_mutation()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'Coin history is append-only; record a compensating transaction'
    using errcode = '23514';
end;
$$;
revoke all on function private.reject_coin_ledger_mutation() from public,anon,authenticated;
create trigger coin_history_append_only before update or delete on public.coin_transactions
for each row execute function private.reject_coin_ledger_mutation();
create trigger coin_history_no_truncate before truncate on public.coin_transactions
for each statement execute function private.reject_coin_ledger_mutation();
revoke insert,update,delete,truncate on public.coin_transactions from public,anon,authenticated;

-- event_id is a stable server-generated business-event identifier, reused on retry.
-- No client may mint coins. Trusted reward handlers must use this service-only RPC.
create or replace function public.record_coin_event(
  p_event_id uuid,p_user_id uuid,p_amount integer,p_reason text,
  p_ref_table text default null,p_ref_id uuid default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare existing public.coin_transactions%rowtype; inserted_id uuid;
begin
  if p_event_id is null or p_user_id is null or p_amount is null or p_amount=0
    or p_reason is null or length(btrim(p_reason)) not between 1 and 500 then
    raise exception 'A stable event ID, account, nonzero amount and reason are required' using errcode='22023';
  end if;
  insert into public.coin_transactions(id,user_id,amount,reason,ref_table,ref_id)
  values(p_event_id,p_user_id,p_amount,btrim(p_reason),p_ref_table,p_ref_id)
  on conflict(id) do nothing returning id into inserted_id;
  if inserted_id is not null then return inserted_id; end if;
  select * into strict existing from public.coin_transactions where id=p_event_id;
  if existing.user_id is distinct from p_user_id or existing.amount is distinct from p_amount
    or existing.reason is distinct from btrim(p_reason) or existing.ref_table is distinct from p_ref_table
    or existing.ref_id is distinct from p_ref_id then
    raise exception 'Coin event ID was already used for a different transaction' using errcode='22023';
  end if;
  return existing.id;
end;
$$;
revoke all on function public.record_coin_event(uuid,uuid,integer,text,text,uuid) from public,anon,authenticated;
grant execute on function public.record_coin_event(uuid,uuid,integer,text,text,uuid) to service_role;

create or replace function private.refresh_profile_badge_count(p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  -- Serialize refreshes for this profile before taking the count snapshot.
  perform 1 from public.profiles where id=p_user_id for update;
  update public.profiles set verified_passport_badge_count=(
    select count(*)::integer from public.user_badges where user_id=p_user_id
  ), updated_at=now() where id=p_user_id;
end;
$$;
create or replace function private.user_badge_count_trigger()
returns trigger language plpgsql security definer set search_path = '' as $$
declare u uuid;
begin
  if tg_op='UPDATE' then
    -- Stable lock ordering for a badge transferred between accounts.
    for u in select distinct x from unnest(array[old.user_id,new.user_id]) x order by x loop
      perform private.refresh_profile_badge_count(u);
    end loop;
  elsif tg_op='DELETE' then
    perform private.refresh_profile_badge_count(old.user_id);
  else
    perform private.refresh_profile_badge_count(new.user_id);
  end if;
  return coalesce(new,old);
end;
$$;
drop trigger trg_user_badge_count on public.user_badges;
create trigger trg_user_badge_count after insert or delete or update of user_id on public.user_badges
for each row execute function private.user_badge_count_trigger();
revoke all on function private.refresh_profile_badge_count(uuid) from public,anon,authenticated;
revoke all on function private.user_badge_count_trigger() from public,anon,authenticated;
-- Repair existing counter drift without changing badge evidence.
update public.profiles p set verified_passport_badge_count=(select count(*)::integer from public.user_badges b where b.user_id=p.id)
where p.verified_passport_badge_count is distinct from (select count(*)::integer from public.user_badges b where b.user_id=p.id);

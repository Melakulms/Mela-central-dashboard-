-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813093109
create or replace function private.ledger_from_arena_reward()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  r record;
  v_count integer;
  v_each numeric;
  v_status text;
  v_when timestamptz;
begin
  if new.reward_type <> 'cash' or coalesce(new.cash_amount,0) <= 0 then return new; end if;
  if new.status not in ('available','paid') then return new; end if;
  if tg_op='UPDATE' and old.status is not distinct from new.status and old.cash_amount is not distinct from new.cash_amount and old.external_ref is not distinct from new.external_ref and old.available_at is not distinct from new.available_at and old.paid_at is not distinct from new.paid_at then return new; end if;
  v_status := case when new.status='paid' then 'paid' else 'available' end;
  v_when := coalesce(case when new.status='paid' then new.paid_at else new.available_at end, now());

  if new.beneficiary_user_id is not null then
    insert into public.earnings_ledger(user_id,source_type,source_id,gross_amount,platform_fee,net_amount,currency,status,external_ref,occurred_at)
    values(new.beneficiary_user_id,'arena_reward',new.id,new.cash_amount,0,new.cash_amount,coalesce(new.currency,'ETB'),v_status,new.external_ref,v_when)
    on conflict(source_type,source_id,user_id) do update set gross_amount=excluded.gross_amount,platform_fee=excluded.platform_fee,net_amount=excluded.net_amount,currency=excluded.currency,status=excluded.status,external_ref=excluded.external_ref,occurred_at=excluded.occurred_at;
    perform private.refresh_work_reputation(new.beneficiary_user_id,null);
  elsif new.beneficiary_arena_team_id is not null then
    select count(*) into v_count from public.arena_team_members where team_id=new.beneficiary_arena_team_id;
    if v_count>0 then
      v_each:=new.cash_amount/v_count;
      for r in select user_id from public.arena_team_members where team_id=new.beneficiary_arena_team_id loop
        insert into public.earnings_ledger(user_id,source_type,source_id,gross_amount,platform_fee,net_amount,currency,status,external_ref,occurred_at)
        values(r.user_id,'arena_reward',new.id,v_each,0,v_each,coalesce(new.currency,'ETB'),v_status,new.external_ref,v_when)
        on conflict(source_type,source_id,user_id) do update set gross_amount=excluded.gross_amount,platform_fee=excluded.platform_fee,net_amount=excluded.net_amount,currency=excluded.currency,status=excluded.status,external_ref=excluded.external_ref,occurred_at=excluded.occurred_at;
        perform private.refresh_work_reputation(r.user_id,null);
      end loop;
    end if;
  elsif new.beneficiary_tournament_team_id is not null then
    select count(*) into v_count from public.arena_tournament_team_members where team_id=new.beneficiary_tournament_team_id;
    if v_count>0 then
      v_each:=new.cash_amount/v_count;
      for r in select user_id from public.arena_tournament_team_members where team_id=new.beneficiary_tournament_team_id loop
        insert into public.earnings_ledger(user_id,source_type,source_id,gross_amount,platform_fee,net_amount,currency,status,external_ref,occurred_at)
        values(r.user_id,'arena_reward',new.id,v_each,0,v_each,coalesce(new.currency,'ETB'),v_status,new.external_ref,v_when)
        on conflict(source_type,source_id,user_id) do update set gross_amount=excluded.gross_amount,platform_fee=excluded.platform_fee,net_amount=excluded.net_amount,currency=excluded.currency,status=excluded.status,external_ref=excluded.external_ref,occurred_at=excluded.occurred_at;
        perform private.refresh_work_reputation(r.user_id,null);
      end loop;
    end if;
  end if;
  return new;
end $$;
;

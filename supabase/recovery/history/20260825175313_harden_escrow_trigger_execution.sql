-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825175313
revoke execute on function private.refresh_contract_finance_from_escrow() from anon, authenticated, public;
revoke execute on function private.enforce_task_milestone_change() from anon, authenticated, public;
revoke execute on function private.guard_payout_account_activation() from anon, authenticated, public;
revoke execute on function private.ledger_from_payout_success() from anon, authenticated, public;
revoke execute on function private.process_milestone_status() from anon, authenticated, public;
revoke execute on function private.sync_escrow_from_milestone() from anon, authenticated, public;
revoke execute on function public.record_milestone_payout(uuid,text,text) from anon, authenticated, public;
revoke execute on function public.record_milestone_escrow_funding(uuid,bigint,text,text) from anon, authenticated, public;
revoke execute on function public.record_escrow_funding(uuid,bigint,text,text) from anon, authenticated, public;
revoke execute on function public.finalize_escrow_payment(uuid,text,text,text,numeric,jsonb) from anon, authenticated, public;
;

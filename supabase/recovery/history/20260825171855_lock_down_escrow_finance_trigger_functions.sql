-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825171855
revoke execute on function private.refresh_contract_finance_from_escrow() from public, anon, authenticated;
revoke execute on function private.enforce_task_milestone_change() from public, anon, authenticated;
revoke execute on function private.guard_payout_account_activation() from public, anon, authenticated;
revoke execute on function private.ledger_from_payout_success() from public, anon, authenticated;
revoke execute on function private.process_milestone_status() from public, anon, authenticated;
revoke execute on function private.sync_escrow_from_milestone() from public, anon, authenticated;

alter default privileges in schema private revoke execute on functions from public, anon, authenticated;
;

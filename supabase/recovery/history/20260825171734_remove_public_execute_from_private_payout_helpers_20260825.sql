-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825171734
revoke execute on function private.guard_payout_account_activation() from public;
revoke execute on function private.ledger_from_payout_success() from public;
revoke execute on function private.process_milestone_status() from public;
revoke execute on function private.sync_escrow_from_milestone() from public;
revoke execute on function private.submit_task_milestone(uuid, text, text) from public;
revoke execute on function private.submit_task_milestone(uuid) from public;
revoke execute on function private.review_task_milestone(uuid, text, text) from public;
revoke execute on function private.withdraw_freelance_proposal(uuid) from public;
revoke execute on function private.create_task_milestone(uuid, text, numeric, timestamptz, text) from public;
grant execute on function private.submit_task_milestone(uuid, text, text) to authenticated, service_role;
grant execute on function private.submit_task_milestone(uuid) to authenticated, service_role;
grant execute on function private.review_task_milestone(uuid, text, text) to authenticated, service_role;
grant execute on function private.withdraw_freelance_proposal(uuid) to authenticated, service_role;
grant execute on function private.create_task_milestone(uuid, text, numeric, timestamptz, text) to authenticated, service_role;
;

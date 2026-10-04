-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825171723
revoke execute on function private.guard_payout_account_activation() from anon, authenticated;
revoke execute on function private.ledger_from_payout_success() from anon, authenticated;
revoke execute on function private.process_milestone_status() from anon, authenticated;
revoke execute on function private.sync_escrow_from_milestone() from anon, authenticated;
-- The trigger-only functions above are invoked by PostgreSQL triggers, not by API callers.
-- Keep user-callable milestone operations authenticated-only.
revoke execute on function private.submit_task_milestone(uuid, text, text) from anon;
revoke execute on function private.submit_task_milestone(uuid) from anon;
revoke execute on function private.review_task_milestone(uuid, text, text) from anon;
revoke execute on function private.withdraw_freelance_proposal(uuid) from anon;
revoke execute on function private.create_task_milestone(uuid, text, numeric, timestamptz, text) from anon;
;

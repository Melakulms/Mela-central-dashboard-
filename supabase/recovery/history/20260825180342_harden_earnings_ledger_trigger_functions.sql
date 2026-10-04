-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825180342
revoke execute on function private.ledger_from_challenge_reward() from public, anon, authenticated;
revoke execute on function private.ledger_from_arena_reward() from public, anon, authenticated;
revoke execute on function private.guard_learning_payment_attempt_fields() from public, anon, authenticated;
;

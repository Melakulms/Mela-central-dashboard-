-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002085954
-- Trigger checks must see the effective caller; authorized SECURITY DEFINER RPCs still run as their owner.
alter function private.prepare_marketplace_task() security invoker;
alter function private.protect_employer_member_identity_fields() security invoker;

;

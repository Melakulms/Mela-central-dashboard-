-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812215437
-- Exact browser privileges for freelance marketplace tables. RLS remains the authorization layer.
revoke all privileges on public.marketplace_tasks from anon,authenticated;
grant select on public.marketplace_tasks to anon,authenticated;
grant insert (posted_by,title,description,task_type,reward_coins,employer_id,budget_amount,currency,deadline,status,skills_required) on public.marketplace_tasks to authenticated;
grant update (title,description,task_type,reward_coins,budget_amount,currency,deadline,status,skills_required) on public.marketplace_tasks to authenticated;
grant delete on public.marketplace_tasks to authenticated;
grant all on public.marketplace_tasks to service_role;

revoke all privileges on public.marketplace_submissions from anon,authenticated;
grant select on public.marketplace_submissions to authenticated;
grant insert (task_id,user_id,content_url,status,proposal_note,bid_amount,currency) on public.marketplace_submissions to authenticated;
grant update (content_url,status,proposal_note,bid_amount) on public.marketplace_submissions to authenticated;
grant all on public.marketplace_submissions to service_role;

revoke all privileges on public.freelance_contracts from anon,authenticated;
grant select on public.freelance_contracts to authenticated;
grant update (terms,status) on public.freelance_contracts to authenticated;
grant all on public.freelance_contracts to service_role;

revoke all privileges on public.task_milestones from anon,authenticated;
grant select on public.task_milestones to authenticated;
grant insert (contract_id,milestone_order,title,description,amount,due_at,status) on public.task_milestones to authenticated;
grant update (milestone_order,title,description,amount,due_at,status,deliverable_url,submission_note,review_note) on public.task_milestones to authenticated;
grant delete on public.task_milestones to authenticated;
grant all on public.task_milestones to service_role;

revoke all privileges on public.escrow_transactions from anon,authenticated;
grant select on public.escrow_transactions to authenticated;
grant all on public.escrow_transactions to service_role;

revoke all privileges on public.escrow_payment_attempts from anon,authenticated;
grant select on public.escrow_payment_attempts to authenticated;
grant all on public.escrow_payment_attempts to service_role;

revoke all privileges on public.payout_requests from anon,authenticated;
grant select on public.payout_requests to authenticated;
grant all on public.payout_requests to service_role;

revoke all privileges on public.payout_accounts from anon,authenticated;
grant select,insert,update,delete on public.payout_accounts to authenticated;
grant all on public.payout_accounts to service_role;

;

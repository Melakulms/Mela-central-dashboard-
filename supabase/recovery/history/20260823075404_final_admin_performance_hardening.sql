-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260823075404
drop index if exists public.platform_operational_alerts_admin_queue_idx;
drop index if exists public.reports_admin_queue_idx;

create index if not exists access_requests_requested_role_id_idx on admin.access_requests(requested_role_id);
create index if not exists access_requests_requester_id_idx on admin.access_requests(requester_id);
create index if not exists access_requests_reviewed_by_idx on admin.access_requests(reviewed_by);
create index if not exists admin_users_role_id_idx on admin.admin_users(role_id);
create index if not exists role_permissions_permission_id_idx on admin.role_permissions(permission_id);
create index if not exists registration_referrals_referral_code_id_idx on public.registration_referrals(referral_code_id);

alter policy referral_codes_owner_select on public.referral_codes using (owner_user_id = (select auth.uid()));
alter policy registration_referrals_participant_select on public.registration_referrals using ((registered_user_id = (select auth.uid())) or (inviter_user_id = (select auth.uid())));

;

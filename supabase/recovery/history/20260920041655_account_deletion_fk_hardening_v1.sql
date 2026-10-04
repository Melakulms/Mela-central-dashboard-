-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260920041655
-- MELA account deletion referential-integrity hardening
-- Personal relationship rows are cascaded; audit/financial/organizational records
-- that may need legitimate retention are detached with SET NULL.

alter table public.installment_plans alter column user_id drop not null;
alter table public.invitation_commissions alter column inviter_user_id drop not null;
alter table public.invitation_commissions alter column registered_user_id drop not null;
alter table public.registration_referrals alter column inviter_user_id drop not null;
alter table public.registration_referrals alter column registered_user_id drop not null;

alter table public.application_notes drop constraint if exists application_notes_author_id_fkey;
alter table public.application_notes add constraint application_notes_author_id_fkey foreign key (author_id) references public.profiles(id) on delete set null;
alter table public.application_notes alter column author_id drop not null;

alter table public.employer_verification_documents drop constraint if exists employer_verification_documents_uploaded_by_fkey;
alter table public.employer_verification_documents add constraint employer_verification_documents_uploaded_by_fkey foreign key (uploaded_by) references public.profiles(id) on delete set null;
alter table public.employer_verification_documents alter column uploaded_by drop not null;

alter table public.employers drop constraint if exists employers_owner_id_fkey;
alter table public.employers add constraint employers_owner_id_fkey foreign key (owner_id) references public.profiles(id) on delete set null;
alter table public.employers alter column owner_id drop not null;

alter table public.sector_partner_organizations drop constraint if exists sector_partner_organizations_owner_id_fkey;
alter table public.sector_partner_organizations add constraint sector_partner_organizations_owner_id_fkey foreign key (owner_id) references public.profiles(id) on delete set null;
alter table public.sector_partner_organizations alter column owner_id drop not null;

alter table public.mentorship_sessions drop constraint if exists mentorship_sessions_mentee_id_fkey;
alter table public.mentorship_sessions add constraint mentorship_sessions_mentee_id_fkey foreign key (mentee_id) references public.profiles(id) on delete set null;
alter table public.mentorship_sessions alter column mentee_id drop not null;
alter table public.mentorship_sessions drop constraint if exists mentorship_sessions_mentor_id_fkey;
alter table public.mentorship_sessions add constraint mentorship_sessions_mentor_id_fkey foreign key (mentor_id) references public.profiles(id) on delete set null;
alter table public.mentorship_sessions alter column mentor_id drop not null;

alter table public.mela_ai_approvals drop constraint if exists mela_ai_approvals_requested_by_fkey;
alter table public.mela_ai_approvals add constraint mela_ai_approvals_requested_by_fkey foreign key (requested_by) references auth.users(id) on delete cascade;
alter table public.mela_ai_approvals alter column requested_by set not null;

alter table public.mela_ai_tasks drop constraint if exists mela_ai_tasks_created_by_fkey;
alter table public.mela_ai_tasks add constraint mela_ai_tasks_created_by_fkey foreign key (created_by) references auth.users(id) on delete cascade;
alter table public.mela_ai_tasks drop constraint if exists mela_ai_tasks_assigned_user_id_fkey;
alter table public.mela_ai_tasks add constraint mela_ai_tasks_assigned_user_id_fkey foreign key (assigned_user_id) references auth.users(id) on delete set null;

alter table public.referral_codes drop constraint if exists referral_codes_owner_user_id_fkey;
alter table public.referral_codes add constraint referral_codes_owner_user_id_fkey foreign key (owner_user_id) references auth.users(id) on delete cascade;

alter table public.invitation_commissions drop constraint if exists invitation_commissions_inviter_user_id_fkey;
alter table public.invitation_commissions add constraint invitation_commissions_inviter_user_id_fkey foreign key (inviter_user_id) references auth.users(id) on delete set null;
alter table public.invitation_commissions drop constraint if exists invitation_commissions_registered_user_id_fkey;
alter table public.invitation_commissions add constraint invitation_commissions_registered_user_id_fkey foreign key (registered_user_id) references auth.users(id) on delete set null;

alter table public.registration_referrals drop constraint if exists registration_referrals_inviter_user_id_fkey;
alter table public.registration_referrals add constraint registration_referrals_inviter_user_id_fkey foreign key (inviter_user_id) references auth.users(id) on delete set null;
alter table public.registration_referrals drop constraint if exists registration_referrals_registered_user_id_fkey;
alter table public.registration_referrals add constraint registration_referrals_registered_user_id_fkey foreign key (registered_user_id) references auth.users(id) on delete set null;
;

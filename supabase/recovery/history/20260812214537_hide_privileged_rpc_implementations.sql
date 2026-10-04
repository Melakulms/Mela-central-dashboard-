-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812214537
-- Move privileged implementations out of the exposed public schema.
-- Public API functions become SECURITY INVOKER wrappers; private implementations retain strict auth checks.

alter function public.cancel_mentorship_request(uuid) set schema private;
alter function public.respond_mentorship_request(uuid,text) set schema private;
alter function public.schedule_mentorship_session(uuid,timestamptz,integer,text) set schema private;
alter function public.cancel_mentorship_session(uuid,text) set schema private;
alter function public.complete_mentorship_session(uuid,text) set schema private;
alter function public.review_mentor_profile(uuid,boolean,text) set schema private;

alter function public.withdraw_freelance_proposal(uuid) set schema private;
alter function public.shortlist_freelance_proposal(uuid) set schema private;
alter function public.award_freelance_task(uuid,numeric,text) set schema private;
alter function public.respond_freelance_contract(uuid,boolean,text) set schema private;
alter function public.create_task_milestone(uuid,text,numeric,timestamptz,text) set schema private;
alter function public.submit_task_milestone(uuid) set schema private;
alter function public.review_task_milestone(uuid,text,text) set schema private;
alter function public.raise_contract_dispute(uuid,text) set schema private;
alter function public.cancel_freelance_contract(uuid,text) set schema private;

alter function public.refresh_candidate_matches(uuid) set schema private;
alter function public.review_proctored_attempt(uuid,text,text) set schema private;

alter function public.review_employer_registration(uuid,text,text) set schema private;
alter function public.review_employer_document(uuid,text,text) set schema private;
alter function public.review_employer_verification(uuid,text,text) set schema private;
alter function public.review_profile_document(uuid,boolean,text,text) set schema private;
alter function public.review_profile_education(uuid,boolean,text,text) set schema private;
alter function public.review_profile_experience(uuid,boolean,text,text) set schema private;
alter function public.review_profile_language(uuid,boolean,text,text) set schema private;
alter function public.review_report(uuid,text,text,uuid) set schema private;

-- Private functions are not API-exposed. Limit their EXECUTE rights to signed-in/service callers used by wrappers.
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname in (
      'cancel_mentorship_request','respond_mentorship_request','schedule_mentorship_session','cancel_mentorship_session','complete_mentorship_session','review_mentor_profile',
      'withdraw_freelance_proposal','shortlist_freelance_proposal','award_freelance_task','respond_freelance_contract','create_task_milestone','submit_task_milestone','review_task_milestone','raise_contract_dispute','cancel_freelance_contract',
      'refresh_candidate_matches','review_proctored_attempt','review_employer_registration','review_employer_document','review_employer_verification',
      'review_profile_document','review_profile_education','review_profile_experience','review_profile_language','review_report'
    )
  loop
    execute format('revoke all on function %s from public, anon',r.sig);
    execute format('grant execute on function %s to authenticated, service_role',r.sig);
  end loop;
end $$;

-- Public invoker wrappers.
create function public.cancel_mentorship_request(p_request_id uuid)
returns public.mentorship_requests language sql security invoker set search_path=''
as $$ select (private.cancel_mentorship_request(p_request_id)).* $$;
create function public.respond_mentorship_request(p_request_id uuid,p_decision text)
returns public.mentorship_requests language sql security invoker set search_path=''
as $$ select (private.respond_mentorship_request(p_request_id,p_decision)).* $$;
create function public.schedule_mentorship_session(p_request_id uuid,p_scheduled_at timestamptz,p_duration_min integer default 30,p_call_room_id text default null)
returns public.mentorship_sessions language sql security invoker set search_path=''
as $$ select (private.schedule_mentorship_session(p_request_id,p_scheduled_at,p_duration_min,p_call_room_id)).* $$;
create function public.cancel_mentorship_session(p_session_id uuid,p_reason text default null)
returns public.mentorship_sessions language sql security invoker set search_path=''
as $$ select (private.cancel_mentorship_session(p_session_id,p_reason)).* $$;
create function public.complete_mentorship_session(p_session_id uuid,p_notes text default null)
returns public.mentorship_sessions language sql security invoker set search_path=''
as $$ select (private.complete_mentorship_session(p_session_id,p_notes)).* $$;
create function public.review_mentor_profile(p_mentor_id uuid,p_verified boolean,p_notes text default null)
returns public.mentor_profiles language sql security invoker set search_path=''
as $$ select (private.review_mentor_profile(p_mentor_id,p_verified,p_notes)).* $$;

create function public.withdraw_freelance_proposal(p_submission_id uuid)
returns public.marketplace_submissions language sql security invoker set search_path=''
as $$ select (private.withdraw_freelance_proposal(p_submission_id)).* $$;
create function public.shortlist_freelance_proposal(p_submission_id uuid)
returns public.marketplace_submissions language sql security invoker set search_path=''
as $$ select (private.shortlist_freelance_proposal(p_submission_id)).* $$;
create function public.award_freelance_task(p_submission_id uuid,p_agreed_amount numeric,p_terms text default null)
returns public.freelance_contracts language sql security invoker set search_path=''
as $$ select (private.award_freelance_task(p_submission_id,p_agreed_amount,p_terms)).* $$;
create function public.respond_freelance_contract(p_contract_id uuid,p_accept boolean,p_reason text default null)
returns public.freelance_contracts language sql security invoker set search_path=''
as $$ select (private.respond_freelance_contract(p_contract_id,p_accept,p_reason)).* $$;
create function public.create_task_milestone(p_contract_id uuid,p_title text,p_amount numeric,p_due_at timestamptz default null,p_description text default null)
returns public.task_milestones language sql security invoker set search_path=''
as $$ select (private.create_task_milestone(p_contract_id,p_title,p_amount,p_due_at,p_description)).* $$;
create function public.submit_task_milestone(p_milestone_id uuid)
returns public.task_milestones language sql security invoker set search_path=''
as $$ select (private.submit_task_milestone(p_milestone_id)).* $$;
create function public.review_task_milestone(p_milestone_id uuid,p_decision text,p_notes text default null)
returns public.task_milestones language sql security invoker set search_path=''
as $$ select (private.review_task_milestone(p_milestone_id,p_decision,p_notes)).* $$;
create function public.raise_contract_dispute(p_contract_id uuid,p_reason text)
returns public.freelance_contracts language sql security invoker set search_path=''
as $$ select (private.raise_contract_dispute(p_contract_id,p_reason)).* $$;
create function public.cancel_freelance_contract(p_contract_id uuid,p_reason text default null)
returns public.freelance_contracts language sql security invoker set search_path=''
as $$ select (private.cancel_freelance_contract(p_contract_id,p_reason)).* $$;

create function public.refresh_candidate_matches(p_opportunity_id uuid)
returns integer language sql security invoker set search_path=''
as $$ select private.refresh_candidate_matches(p_opportunity_id) $$;
create function public.review_proctored_attempt(p_attempt_id uuid,p_decision text,p_notes text default null)
returns public.assessment_attempts language sql security invoker set search_path=''
as $$ select (private.review_proctored_attempt(p_attempt_id,p_decision,p_notes)).* $$;

create function public.review_employer_registration(p_request_id uuid,p_decision text,p_notes text default null)
returns public.employer_registration_requests language sql security invoker set search_path=''
as $$ select (private.review_employer_registration(p_request_id,p_decision,p_notes)).* $$;
create function public.review_employer_document(p_document_id uuid,p_decision text,p_notes text default null)
returns public.employer_verification_documents language sql security invoker set search_path=''
as $$ select (private.review_employer_document(p_document_id,p_decision,p_notes)).* $$;
create function public.review_employer_verification(p_employer_id uuid,p_status text,p_notes text default null)
returns public.employers language sql security invoker set search_path=''
as $$ select (private.review_employer_verification(p_employer_id,p_status,p_notes)).* $$;
create function public.review_profile_document(p_document_id uuid,p_verified boolean,p_source text default null,p_notes text default null)
returns public.profile_documents language sql security invoker set search_path=''
as $$ select (private.review_profile_document(p_document_id,p_verified,p_source,p_notes)).* $$;
create function public.review_profile_education(p_education_id uuid,p_verified boolean,p_source text default null,p_notes text default null)
returns public.profile_education language sql security invoker set search_path=''
as $$ select (private.review_profile_education(p_education_id,p_verified,p_source,p_notes)).* $$;
create function public.review_profile_experience(p_experience_id uuid,p_verified boolean,p_source text default null,p_notes text default null)
returns public.profile_experience language sql security invoker set search_path=''
as $$ select (private.review_profile_experience(p_experience_id,p_verified,p_source,p_notes)).* $$;
create function public.review_profile_language(p_language_id uuid,p_verified boolean,p_source text default null,p_notes text default null)
returns public.profile_languages language sql security invoker set search_path=''
as $$ select (private.review_profile_language(p_language_id,p_verified,p_source,p_notes)).* $$;
create function public.review_report(p_report_id uuid,p_status text,p_notes text default null,p_assigned_to uuid default null)
returns public.reports language sql security invoker set search_path=''
as $$ select (private.review_report(p_report_id,p_status,p_notes,p_assigned_to)).* $$;

-- API exposure: wrappers only.
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in (
      'cancel_mentorship_request','respond_mentorship_request','schedule_mentorship_session','cancel_mentorship_session','complete_mentorship_session','review_mentor_profile',
      'withdraw_freelance_proposal','shortlist_freelance_proposal','award_freelance_task','respond_freelance_contract','create_task_milestone','submit_task_milestone','review_task_milestone','raise_contract_dispute','cancel_freelance_contract',
      'refresh_candidate_matches','review_proctored_attempt','review_employer_registration','review_employer_document','review_employer_verification',
      'review_profile_document','review_profile_education','review_profile_experience','review_profile_language','review_report'
    )
  loop
    execute format('revoke all on function %s from public, anon',r.sig);
    execute format('grant execute on function %s to authenticated, service_role',r.sig);
  end loop;
end $$;
;

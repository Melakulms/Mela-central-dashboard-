-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814165434
create table if not exists public.data_protection_processing_activities (
  activity_key text primary key,
  activity_name text not null,
  purpose text not null,
  data_subject_categories text[] not null default '{}',
  personal_data_categories text[] not null default '{}',
  sensitive_data boolean not null default false,
  lawful_basis_draft text,
  systems text[] not null default '{}',
  recipients text[] not null default '{}',
  cross_border boolean not null default false,
  retention_draft text,
  status text not null default 'draft' check(status in ('draft','reviewed','approved','retired')),
  legal_review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.data_protection_processors (
  processor_key text primary key,
  processor_name text not null,
  service_purpose text not null,
  active boolean not null default false,
  data_categories text[] not null default '{}',
  known_processing_region text,
  international_transfer boolean not null default false,
  contract_dpa_status text not null default 'unverified' check(contract_dpa_status in ('unverified','review_required','verified','not_applicable')),
  transfer_basis_status text not null default 'review_required' check(transfer_basis_status in ('review_required','documented','not_applicable')),
  safeguards_draft text,
  evidence_reference text,
  owner_notes text,
  last_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.data_protection_retention_register (
  record_category text primary key,
  systems text[] not null default '{}',
  retention_rule_draft text not null,
  deletion_or_archive_action text not null,
  exceptions text,
  legal_status text not null default 'draft' check(legal_status in ('draft','counsel_review','approved')),
  updated_at timestamptz not null default now()
);

create table if not exists public.data_protection_dpia_register (
  dpia_key text primary key,
  feature_name text not null,
  risk_reason text not null,
  personal_data_categories text[] not null default '{}',
  risks jsonb not null default '[]'::jsonb,
  mitigations jsonb not null default '[]'::jsonb,
  residual_risk text,
  status text not null default 'draft' check(status in ('draft','review_required','approved','retired')),
  reviewer_notes text,
  updated_at timestamptz not null default now()
);

create table if not exists public.data_protection_incidents (
  id uuid primary key default gen_random_uuid(),
  detected_at timestamptz not null default now(),
  detected_by uuid references public.profiles(id) on delete set null,
  severity text not null default 'investigating' check(severity in ('investigating','low','medium','high','critical')),
  incident_type text not null,
  systems_affected text[] not null default '{}',
  data_categories text[] not null default '{}',
  estimated_subjects integer,
  contained_at timestamptz,
  authority_notification_required boolean,
  authority_notified_at timestamptz,
  subject_notification_required boolean,
  subjects_notified_at timestamptz,
  root_cause text,
  actions_taken text,
  status text not null default 'open' check(status in ('open','contained','resolved','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.data_protection_processing_activities enable row level security;
alter table public.data_protection_processors enable row level security;
alter table public.data_protection_retention_register enable row level security;
alter table public.data_protection_dpia_register enable row level security;
alter table public.data_protection_incidents enable row level security;

revoke all on public.data_protection_processing_activities from anon,authenticated;
revoke all on public.data_protection_processors from anon,authenticated;
revoke all on public.data_protection_retention_register from anon,authenticated;
revoke all on public.data_protection_dpia_register from anon,authenticated;
revoke all on public.data_protection_incidents from anon,authenticated;
grant select on public.data_protection_processing_activities,public.data_protection_processors,public.data_protection_retention_register,public.data_protection_dpia_register,public.data_protection_incidents to authenticated;

create policy dp_processing_admin_read on public.data_protection_processing_activities for select to authenticated using(private.is_admin_user());
create policy dp_processors_admin_read on public.data_protection_processors for select to authenticated using(private.is_admin_user());
create policy dp_retention_admin_read on public.data_protection_retention_register for select to authenticated using(private.is_admin_user());
create policy dp_dpia_admin_read on public.data_protection_dpia_register for select to authenticated using(private.is_admin_user());
create policy dp_incidents_admin_read on public.data_protection_incidents for select to authenticated using(private.is_admin_user());

insert into public.data_protection_processing_activities(activity_key,activity_name,purpose,data_subject_categories,personal_data_categories,sensitive_data,lawful_basis_draft,systems,recipients,cross_border,retention_draft,status,legal_review_notes) values
('account_auth','Account, authentication and security','Create and secure user accounts and prevent unauthorized access.',array['users'],array['name','email','phone','authentication identifiers','security events'],false,'Service/contract and security obligations — counsel confirmation required.',array['Supabase Auth','profiles','platform_events'],array['authentication infrastructure'],true,'Account lifecycle plus security/fraud retention; exact periods require counsel approval.','reviewed','Technical controls implemented; final lawful basis/retention require legal review.'),
('career_passport','Career Passport and verified skills','Build user-controlled career evidence and verified skill records.',array['students','talent'],array['education','experience','projects','languages','documents','assessment results','verified skills'],true,'Service/contract; explicit consent may apply to sensitive documents — counsel confirmation required.',array['profiles','profile_*','verified_skills','skill assessments'],array['verified employers only when user applies/shares'],false,'User-controlled account lifecycle with lawful retention exceptions.','reviewed','Verified evidence is separated from self-claims.'),
('learning_ai','Learning and AI assistance','Provide Academy, Practice, AI Tutor and Career Coach services.',array['students','talent'],array['learning progress','practice responses','AI prompts and responses','career context'],false,'Service/contract and user-requested AI processing — counsel confirmation required.',array['Academy','Practice','AI Tutor','Career Coach'],array['OpenAI for enabled AI requests'],true,'Minimize prompt/history storage; exact retention requires counsel approval.','reviewed','AI is not allowed to issue verified credentials or make hiring/payment decisions.'),
('assessment_proctoring','Assessment and browser proctoring','Verify skills and protect assessment integrity.',array['assessment candidates'],array['assessment responses','browser integrity events','camera permission state','focus/fullscreen/network events'],true,'Explicit proctoring consent plus service integrity — counsel confirmation required.',array['assessment_*','proctor_*'],array['authorized Mela reviewers'],false,'Retain long enough for review/appeal; exact period requires counsel approval.','reviewed','Current browser flow does not perform trusted face recognition.'),
('opportunities_hiring','Opportunities, applications and hiring','Allow users to discover, save and apply to opportunities and allow verified employers to review applicants.',array['students','talent','employer staff'],array['Career Passport snapshot','application status','screening responses','interviews'],false,'User-requested application / service performance — counsel confirmation required.',array['opportunities','applications','interviews','candidate_matches'],array['verified employer for applied opportunity','official external source when user leaves Mela'],false,'Application and hiring records subject to user rights and legitimate dispute/fraud retention.','reviewed','External official-source opportunities do not transmit Career Passport to Mela employer accounts.'),
('work_finance','Freelance work, escrow and payouts','Manage tasks, contracts, milestones, escrow, earnings and payouts when enabled.',array['freelancers','employers'],array['work submissions','contracts','messages','payment references','payout account details'],true,'Contract/performance and financial/legal obligations — launch requires counsel/provider review.',array['marketplace_*','freelance_*','escrow_*','earnings_ledger','payout_*'],array['payment/KYC providers when enabled'],true,'Financial/reconciliation records may require extended lawful retention; counsel/tax confirmation required.','draft','Payments and payouts remain disabled.'),
('support_compliance','Support, moderation, audit and data rights','Handle safety reports, admin audit, privacy requests and compliance investigations.',array['all users','admins'],array['support/report content','audit events','data-rights requests','incident records'],true,'Legal/compliance/security obligations and user requests — counsel confirmation required.',array['reports','admin_audit_logs','data_subject_requests','data_protection_*'],array['ECA/qualified authorities where legally required'],false,'Retain only as required to resolve requests/incidents and satisfy lawful obligations.','reviewed','Data-rights workflow is implemented in product.')
on conflict(activity_key) do update set activity_name=excluded.activity_name,purpose=excluded.purpose,data_subject_categories=excluded.data_subject_categories,personal_data_categories=excluded.personal_data_categories,sensitive_data=excluded.sensitive_data,lawful_basis_draft=excluded.lawful_basis_draft,systems=excluded.systems,recipients=excluded.recipients,cross_border=excluded.cross_border,retention_draft=excluded.retention_draft,status=excluded.status,legal_review_notes=excluded.legal_review_notes,updated_at=now();

insert into public.data_protection_processors(processor_key,processor_name,service_purpose,active,data_categories,known_processing_region,international_transfer,contract_dpa_status,transfer_basis_status,safeguards_draft,evidence_reference,owner_notes,last_verified_at) values
('supabase','Supabase','Database, authentication, storage and Edge Functions',true,array['account data','profile data','application data','learning data','work/finance records','security logs'],'eu-west-1 (project region)',true,'review_required','review_required','Encryption/access controls/RLS implemented; contract/DPA and Ethiopian transfer basis require review.','Mela Supabase project configuration','Primary application infrastructure.',now()),
('openai','OpenAI','AI Tutor, Career Coach, Practice Coach and localization requests',true,array['user prompts','course/career context','practice response excerpts','text requiring localization'],'International processing — exact contractual processing locations require DPA review',true,'review_required','review_required','Minimize data sent; no service-role secrets; requests use user-scoped safety identifiers; DPA/transfer basis requires review.','Mela Edge Functions: ai-tutor, career-coach, practice-coach, mela-localize','Do not send assessment answer keys or unrelated private data.',now()),
('vercel','Vercel','Future web hosting and Vercel Functions for production candidate',false,array['web requests','authentication refresh cookie handled by Mela auth functions','runtime logs'],'Not active for Mela production',true,'unverified','review_required','Candidate uses HttpOnly refresh cookie and no service-role key; activate only after staging/legal review.','Mela Production Candidate v5','Not yet verified as active Mela production processor.',now()),
('chapa','Chapa','Course/escrow payment initiation and verification when Payments is enabled',false,array['payment reference','payer transaction data'],'Provider-specific; verify contract and processing locations before enablement',false,'unverified','review_required','Payments OFF. Verify provider contract, KYC, security and transfer facts before activation.','Mela Chapa Edge Functions','Do not infer processing geography until provider documentation is verified.',now()),
('email_provider','Production email provider — TBD','Authentication and transactional email',false,array['email address','message metadata'],'TBD',true,'unverified','review_required','Select provider and review DPA/transfer safeguards before production SMTP activation.',null,'Custom SMTP blocker remains open.',null),
('sms_provider','Production SMS/OTP provider — TBD','Phone verification / OTP if launched',false,array['phone number','OTP metadata'],'TBD',true,'unverified','review_required','Optional launch feature; keep disabled until provider selected and reviewed.',null,'SMS OTP is not required for current launch scope.',null)
on conflict(processor_key) do update set processor_name=excluded.processor_name,service_purpose=excluded.service_purpose,active=excluded.active,data_categories=excluded.data_categories,known_processing_region=excluded.known_processing_region,international_transfer=excluded.international_transfer,contract_dpa_status=excluded.contract_dpa_status,transfer_basis_status=excluded.transfer_basis_status,safeguards_draft=excluded.safeguards_draft,evidence_reference=excluded.evidence_reference,owner_notes=excluded.owner_notes,last_verified_at=excluded.last_verified_at,updated_at=now();

insert into public.data_protection_retention_register(record_category,systems,retention_rule_draft,deletion_or_archive_action,exceptions,legal_status) values
('Account and profile',array['auth.users','profiles','profile_*'],'Retain while account is active; process erasure requests subject to narrowly documented lawful exceptions.','Delete or de-identify user-controlled records after approved erasure workflow.','Security, disputes or other lawful retention only where documented.','counsel_review'),
('Assessment and proctoring',array['assessment_*','proctor_*'],'Retain for integrity review, appeal and credential verification; exact period to be approved before launch.','Delete/de-identify raw integrity events after approved period while preserving lawful credential audit evidence as needed.','Active fraud/integrity investigation or legal hold.','counsel_review'),
('Applications and interviews',array['applications','interviews','application_*'],'Retain for user tracking and employer process, then delete/de-identify according to approved hiring-record schedule.','Delete/de-identify expired process records unless dispute/legal basis requires retention.','Open dispute, fraud or legal obligation.','counsel_review'),
('AI and learning interactions',array['career_coach_*','ai_coach_sessions','practice_*','student_*_progress'],'Keep only what is required for user continuity, safety and learning progress; minimize raw conversation retention.','Delete user-requested content where no overriding lawful basis applies.','Security abuse investigation or user-requested active plan continuity.','counsel_review'),
('Financial and work records',array['freelance_*','escrow_*','earnings_ledger','payout_*'],'Retain according to final Ethiopian financial/tax/dispute requirements once provider/legal review is complete.','Archive securely then delete after legally required period.','Tax, AML/KYC, dispute, fraud and reconciliation obligations.','counsel_review'),
('Security and admin audit',array['platform_events','admin_audit_logs','reports','data_protection_incidents'],'Retain according to documented security investigation and accountability needs; exact periods require approval.','Rotate/delete after approved security retention period.','Active incident, legal hold or regulator request.','counsel_review')
on conflict(record_category) do update set systems=excluded.systems,retention_rule_draft=excluded.retention_rule_draft,deletion_or_archive_action=excluded.deletion_or_archive_action,exceptions=excluded.exceptions,legal_status=excluded.legal_status,updated_at=now();

insert into public.data_protection_dpia_register(dpia_key,feature_name,risk_reason,personal_data_categories,risks,mitigations,residual_risk,status,reviewer_notes) values
('proctored_assessments','Proctored skill assessments','Integrity monitoring can affect credential outcomes and involves potentially sensitive behavioral/device signals.',array['assessment responses','browser integrity signals','camera permission state'],jsonb_build_array('Over-collection','False positive integrity flags','Unfair automated credential denial'),jsonb_build_array('Explicit consent','No trusted face recognition in current browser flow','Human/admin review before verified skill when required','Private answer keys','Audit logs'),'Medium pending legal/privacy review.','review_required','Product controls implemented; final DPIA sign-off required.'),
('ai_career_learning','AI Tutor / Career Coach / Practice Coach / Localization','AI processing can expose contextual personal data and produce incorrect or biased guidance.',array['prompts','career context','learning context','practice answers'],jsonb_build_array('Excess data disclosure','Hallucinated advice','Bias','Inappropriate automated reliance'),jsonb_build_array('Feature-specific data minimization','No AI hiring/payment/credential decisions','Daily limits','User disclosure','Service-side feature kill switches'),'Medium pending DPA/transfer review.','review_required','Human verification is required for important outcomes.'),
('career_matching','Career Passport opportunity matching','Automated scoring can influence which opportunities/candidates are surfaced.',array['verified skills','education','experience','application data'],jsonb_build_array('Bias or unfair ranking','Over-reliance on score','Incorrect profile evidence'),jsonb_build_array('Transparent factor breakdown','Verified evidence distinction','Score does not guarantee selection','Employer/human decision remains separate'),'Medium pending legal review of automated-decision obligations.','review_required','Matching does not make hiring decisions.'),
('work_finance','Earn & Work / escrow / payouts','Financial and identity data can create fraud, loss and legal risks.',array['contracts','milestones','payment references','payout account data'],jsonb_build_array('Unauthorized money movement','Fraud','Incorrect settlement','Sensitive financial data exposure'),jsonb_build_array('Payments/Payouts OFF until provider verification','Exact milestone escrow state machine','Provider verification/reconciliation','RLS and service-side finance controls'),'High until provider/KYC/legal controls are completed.','draft','Do not enable Payments/Payouts yet.')
on conflict(dpia_key) do update set feature_name=excluded.feature_name,risk_reason=excluded.risk_reason,personal_data_categories=excluded.personal_data_categories,risks=excluded.risks,mitigations=excluded.mitigations,residual_risk=excluded.residual_risk,status=excluded.status,reviewer_notes=excluded.reviewer_notes,updated_at=now();

create or replace function private.get_data_protection_compliance_pack()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v jsonb; begin
 if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
 select jsonb_build_object(
  'processing_activities',coalesce((select jsonb_agg(to_jsonb(x) order by activity_key) from public.data_protection_processing_activities x),'[]'::jsonb),
  'processors',coalesce((select jsonb_agg(to_jsonb(x) order by processor_key) from public.data_protection_processors x),'[]'::jsonb),
  'retention',coalesce((select jsonb_agg(to_jsonb(x) order by record_category) from public.data_protection_retention_register x),'[]'::jsonb),
  'dpias',coalesce((select jsonb_agg(to_jsonb(x) order by dpia_key) from public.data_protection_dpia_register x),'[]'::jsonb),
  'open_incidents',(select count(*) from public.data_protection_incidents where status in ('open','contained')),
  'registration_fields_ready',jsonb_build_object('processing_activity_count',(select count(*) from public.data_protection_processing_activities),'processor_inventory_count',(select count(*) from public.data_protection_processors),'retention_categories',(select count(*) from public.data_protection_retention_register),'dpia_count',(select count(*) from public.data_protection_dpia_register))
 ) into v; return v; end $$;
create or replace function public.get_data_protection_compliance_pack() returns jsonb language sql set search_path='' as $$ select private.get_data_protection_compliance_pack(); $$;
revoke execute on function private.get_data_protection_compliance_pack() from public,anon;
grant execute on function private.get_data_protection_compliance_pack() to authenticated,service_role;
revoke execute on function public.get_data_protection_compliance_pack() from public,anon;
grant execute on function public.get_data_protection_compliance_pack() to authenticated;

update public.platform_launch_requirements
set evidence_note='Internal ECA-ready processor/activity/retention/DPIA registers created. Active cross-border processors still require contract/DPA and Ethiopian transfer-basis/safeguard review before this blocker can be completed.',updated_at=now()
where requirement_key='cross_border_register';
;

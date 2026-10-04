-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261003042219
do $migration$
declare
  v_admin uuid;
begin
  select au.user_id into v_admin
  from admin.admin_users au
  join public.profiles p on p.id=au.user_id
  where au.active=true and p.account_status='active' and p.deleted_at is null
  order by au.user_id
  limit 1;

  if v_admin is null then
    raise exception 'active admin registry user required to curate launch opportunities';
  end if;

  insert into public.opportunities(
    posted_by,title,description,organization,location,is_remote,external_url,deadline,status,
    organization_name,sector_category,opportunity_type,employment_type_label,stipend_or_reward,
    requirements,verified_source,skills_required,experience_level,education_level,summary,
    work_arrangement,application_method,application_instructions,published_at,source_type,source_url,
    source_verified_at,source_verified_by,source_notes,source_last_checked_at,moderation_status,
    moderation_notes,reviewed_by,reviewed_at
  )
  select v_admin,'UBC International Scholars Program — 2027 Entry',
    'University of British Columbia International Scholars Program for international undergraduate applicants entering the 2027 academic year. The official UBC admissions calendar lists the International Scholars Program application and UBC application deadline as 15 November 2026.',
    'University of British Columbia','Vancouver, Canada',false,
    'https://you.ubc.ca/applying-ubc/dates-deadlines/','2026-11-15','open',
    'University of British Columbia','Education & Social Sciences'::public.launch_category,'scholarships'::public.opportunity_type,
    'Undergraduate scholarship','International Scholars Program awards; award value varies by scholar and demonstrated need',
    array['International applicant','Apply to UBC by the scholarship deadline','Meet the official International Scholars Program eligibility requirements'],
    'University of British Columbia Undergraduate Programs and Admissions',array['Academic excellence','Leadership','Community impact'],null,'Secondary school / undergraduate entry',
    'Official UBC scholarship route for international students seeking undergraduate study in 2027.',
    'onsite','external','Apply only through the official UBC admissions and International Scholars Program process.',now(),
    'official_external','https://you.ubc.ca/applying-ubc/dates-deadlines/',now(),v_admin,
    'Official UBC dates/deadlines page verified for the 15 November 2026 International Scholars Program deadline.',now(),'approved',
    'Official university source verified for launch catalog.',v_admin,now()
  where not exists(select 1 from public.opportunities where source_url='https://you.ubc.ca/applying-ubc/dates-deadlines/' and title='UBC International Scholars Program — 2027 Entry');

  insert into public.opportunities(
    posted_by,title,description,organization,location,is_remote,external_url,deadline,status,
    organization_name,sector_category,opportunity_type,employment_type_label,stipend_or_reward,
    requirements,verified_source,skills_required,experience_level,education_level,summary,
    work_arrangement,application_method,application_instructions,published_at,source_type,source_url,
    source_verified_at,source_verified_by,source_notes,source_last_checked_at,moderation_status,
    moderation_notes,reviewed_by,reviewed_at
  )
  select v_admin,'Lester B. Pearson International Scholarship — University of Toronto 2027',
    'University of Toronto scholarship for outstanding international students entering undergraduate study in September 2027. School nomination closes 9 October 2026, admission application closes 16 October 2026, and the scholarship application/document deadline is 6 November 2026.',
    'University of Toronto','Toronto, Canada',false,
    'https://future.utoronto.ca/pearson-scholarships','2026-11-06','open',
    'University of Toronto','Education & Social Sciences'::public.launch_category,'scholarships'::public.opportunity_type,
    'Undergraduate scholarship','Tuition, books, incidental fees and full residence support for four years',
    array['International student requiring a Canadian study permit','Final year of secondary school in 2026/27 or graduated no earlier than June 2026','School nomination required by 9 October 2026','Begin University of Toronto studies in September 2027'],
    'University of Toronto Future Students',array['Academic excellence','Creativity','Leadership','School nomination'],null,'Secondary school / undergraduate entry',
    'Fully supported four-year University of Toronto scholarship for selected international undergraduate entrants.',
    'onsite','external','Follow the official school nomination, University of Toronto admission, and Pearson scholarship application sequence.',now(),
    'official_external','https://future.utoronto.ca/pearson-scholarships',now(),v_admin,
    'Official University of Toronto Pearson Scholarship page verified with 2026 nomination, admission and scholarship deadlines.',now(),'approved',
    'Official university source verified for launch catalog.',v_admin,now()
  where not exists(select 1 from public.opportunities where source_url='https://future.utoronto.ca/pearson-scholarships' and title='Lester B. Pearson International Scholarship — University of Toronto 2027');

  insert into public.opportunities(
    posted_by,title,description,organization,location,is_remote,external_url,deadline,status,
    organization_name,sector_category,opportunity_type,employment_type_label,stipend_or_reward,
    requirements,verified_source,skills_required,experience_level,education_level,summary,
    work_arrangement,application_method,application_instructions,published_at,source_type,source_url,
    source_verified_at,source_verified_by,source_notes,source_last_checked_at,moderation_status,
    moderation_notes,reviewed_by,reviewed_at
  )
  select v_admin,'EPFL Master Excellence Fellowship — 2027',
    'EPFL Excellence Fellowship for candidates applying to an EPFL Master program. External candidates apply through the Master online application and must have the application paid and validated by 15 December.',
    'EPFL','Lausanne, Switzerland',false,
    'https://www.epfl.ch/education/master/master-excellence-fellowships/how-to-apply/','2026-12-15','open',
    'EPFL','Education & Social Sciences'::public.launch_category,'scholarships'::public.opportunity_type,
    'Master excellence fellowship','CHF 10,000 per semester for up to four semesters; external candidates also receive a student-room reservation benefit',
    array['Apply to an EPFL Master program','Indicate consideration for the Excellence Fellowship in the Master application','Meet EPFL Master admission and fellowship eligibility requirements'],
    'EPFL Master Excellence Fellowships',array['Academic excellence','Master study','Motivation'],null,'Bachelor degree / Master entry',
    'Competitive EPFL fellowship supporting excellent Master candidates.',
    'onsite','external','Apply through the official EPFL Master online application and select consideration for the Excellence Fellowship.',now(),
    'official_external','https://www.epfl.ch/education/master/master-excellence-fellowships/how-to-apply/',now(),v_admin,
    'Official EPFL fellowship application page verified with 15 December deadline and published fellowship benefits.',now(),'approved',
    'Official university source verified for launch catalog.',v_admin,now()
  where not exists(select 1 from public.opportunities where source_url='https://www.epfl.ch/education/master/master-excellence-fellowships/how-to-apply/' and title='EPFL Master Excellence Fellowship — 2027');

  insert into public.opportunities(
    posted_by,title,description,organization,location,is_remote,external_url,deadline,status,
    organization_name,sector_category,opportunity_type,employment_type_label,stipend_or_reward,
    requirements,verified_source,skills_required,experience_level,education_level,summary,
    work_arrangement,application_method,application_instructions,published_at,source_type,source_url,
    source_verified_at,source_verified_by,source_notes,source_last_checked_at,moderation_status,
    moderation_notes,reviewed_by,reviewed_at
  )
  select v_admin,'Security Manager (P-4) — UNICEF Ethiopia #107113',
    'UNICEF Ethiopia fixed-term Security Manager role leading strategic security risk management, security operations and compliance, emergency preparedness and stakeholder coordination in Addis Ababa. The official vacancy is for non-Ethiopian nationals.',
    'UNICEF','Addis Ababa, Ethiopia',false,
    'https://jobs.unicef.org/en-us/job/595959/security-manager-p4-ft-107113-addis-ababa-ethiopia-esar-for-nonethiopian-nationals-only','2026-10-08','open',
    'UNICEF Ethiopia','Education & Social Sciences'::public.launch_category,'jobs'::public.opportunity_type,
    'P-4 Fixed Term Appointment','UNICEF P-4 compensation and benefits; see official vacancy',
    array['Non-Ethiopian nationals only','Advanced degree in security, international relations, conflict analysis or related field','At least eight years of relevant international security management experience','See official vacancy for complete requirements'],
    'UNICEF Careers',array['Security risk management','Emergency preparedness','Stakeholder coordination','Security operations'],'Senior','Advanced degree',
    'Senior UNICEF Ethiopia security leadership role based in Addis Ababa.',
    'onsite','external','Apply only through UNICEF Careers before the official deadline.',now(),
    'official_external','https://jobs.unicef.org/en-us/job/595959/security-manager-p4-ft-107113-addis-ababa-ethiopia-esar-for-nonethiopian-nationals-only',now(),v_admin,
    'Official UNICEF Careers vacancy verified; advertised 1 October 2026 and closes 8 October 2026 EAT.',now(),'approved',
    'Official UNICEF source verified for launch catalog.',v_admin,now()
  where not exists(select 1 from public.opportunities where source_url='https://jobs.unicef.org/en-us/job/595959/security-manager-p4-ft-107113-addis-ababa-ethiopia-esar-for-nonethiopian-nationals-only');

  insert into public.opportunities(
    posted_by,title,description,organization,location,is_remote,external_url,deadline,status,
    organization_name,sector_category,opportunity_type,employment_type_label,stipend_or_reward,
    requirements,verified_source,skills_required,experience_level,education_level,summary,
    work_arrangement,application_method,application_instructions,published_at,source_type,source_url,
    source_verified_at,source_verified_by,source_notes,source_last_checked_at,moderation_status,
    moderation_notes,reviewed_by,reviewed_at
  )
  select v_admin,'Health Manager — UNICEF Ethiopia #00046937',
    'UNICEF Ethiopia Health Manager role supporting equitable and resilient health services, primary health care, immunization, health systems, and health emergency preparedness and response across Ethiopia.',
    'UNICEF','Addis Ababa, Ethiopia',false,
    'https://jobs.unicef.org/mob/cw/en-us/job/595958/health-manager-immunization-health-systems-and-health-emergencies-p4-ft-00046937-addis-ababa-ethiopia-esar','2026-10-08','open',
    'UNICEF Ethiopia','Health & Sciences'::public.launch_category,'jobs'::public.opportunity_type,
    'P-4 Fixed Term Appointment','UNICEF P-4 compensation and benefits; see official vacancy',
    array['Senior health-program experience appropriate to a P-4 role','Expertise in immunization, health systems and/or health emergencies','See official vacancy for complete education and experience requirements'],
    'UNICEF Careers',array['Public health','Immunization','Health systems','Emergency preparedness'],'Senior','Advanced professional qualification',
    'Senior health systems and emergencies role with UNICEF Ethiopia.',
    'onsite','external','Apply only through UNICEF Careers before the official deadline.',now(),
    'official_external','https://jobs.unicef.org/mob/cw/en-us/job/595958/health-manager-immunization-health-systems-and-health-emergencies-p4-ft-00046937-addis-ababa-ethiopia-esar',now(),v_admin,
    'Official UNICEF Careers vacancy verified; advertised 28 September 2026 and closes 8 October 2026 EAT.',now(),'approved',
    'Official UNICEF source verified for launch catalog.',v_admin,now()
  where not exists(select 1 from public.opportunities where source_url='https://jobs.unicef.org/mob/cw/en-us/job/595958/health-manager-immunization-health-systems-and-health-emergencies-p4-ft-00046937-addis-ababa-ethiopia-esar');

  insert into public.opportunities(
    posted_by,title,description,organization,location,is_remote,external_url,deadline,status,
    organization_name,sector_category,opportunity_type,employment_type_label,stipend_or_reward,
    requirements,verified_source,skills_required,experience_level,education_level,summary,
    work_arrangement,application_method,application_instructions,published_at,source_type,source_url,
    source_verified_at,source_verified_by,source_notes,source_last_checked_at,moderation_status,
    moderation_notes,reviewed_by,reviewed_at
  )
  select v_admin,'Social & Behavior Change Specialist (NO-3) — UNICEF Ethiopia #00133327',
    'UNICEF Ethiopia Social and Behavior Change Specialist role leading health SBC and community engagement work supporting the 2025–2030 country programme, including evidence-based, gender-responsive and disability-inclusive approaches.',
    'UNICEF','Addis Ababa, Ethiopia',false,
    'https://jobs.unicef.org/en-us/search/?location=ethiopia&search-keyword=','2026-10-05','open',
    'UNICEF Ethiopia','Health & Sciences'::public.launch_category,'jobs'::public.opportunity_type,
    'NO-3 Fixed Term Appointment','UNICEF national officer compensation and benefits; see official vacancy',
    array['For Ethiopian nationals only','Relevant experience in social and behavior change and community engagement','See official UNICEF vacancy for complete education and experience requirements'],
    'UNICEF Careers Ethiopia vacancy search',array['Social and behavior change','Community engagement','Public health','Programme leadership'],'Experienced professional','Professional degree / qualification per UNICEF vacancy',
    'UNICEF Ethiopia national specialist role in health-related social and behavior change.',
    'onsite','external','Open the official UNICEF Ethiopia vacancies page and apply to vacancy #00133327 before the deadline.',now(),
    'official_external','https://jobs.unicef.org/en-us/search/?location=ethiopia&search-keyword=',now(),v_admin,
    'Official UNICEF Ethiopia current-vacancies page verified vacancy #00133327 with 5 October 2026 deadline.',now(),'approved',
    'Official UNICEF source verified for launch catalog.',v_admin,now()
  where not exists(select 1 from public.opportunities where title='Social & Behavior Change Specialist (NO-3) — UNICEF Ethiopia #00133327');

  insert into public.opportunities(
    posted_by,title,description,organization,location,is_remote,external_url,deadline,status,
    organization_name,sector_category,opportunity_type,employment_type_label,stipend_or_reward,
    requirements,verified_source,skills_required,experience_level,education_level,summary,
    work_arrangement,application_method,application_instructions,published_at,source_type,source_url,
    source_verified_at,source_verified_by,source_notes,source_last_checked_at,moderation_status,
    moderation_notes,reviewed_by,reviewed_at
  )
  select v_admin,'Senior Economic & Public Finance Consultant — UNICEF Ethiopia #595328',
    'UNICEF consultancy focused on debt and social-sector financing in Ethiopia, combining empirical analysis, political-economy analysis and policy-reform analysis to develop recommendations on fiscal space for child-relevant social sectors.',
    'UNICEF','Addis Ababa, Ethiopia / Remote',true,
    'https://jobs.unicef.org/en-us/search/?search-keyword=ethiopia','2026-10-11','open',
    'UNICEF Ethiopia','Business & Finance'::public.launch_category,'jobs'::public.opportunity_type,
    'National/International Consultancy — 7.5 months','Consultancy remuneration per UNICEF terms; see official vacancy',
    array['Senior economics/public-finance expertise','Ability to conduct empirical and political-economy analysis','See official UNICEF vacancy #595328 for full eligibility and deliverables'],
    'UNICEF Careers',array['Public finance','Economics','Debt analysis','Policy analysis','Social-sector financing'],'Senior consultant','Advanced economics/public finance expertise',
    'Senior UNICEF consultancy on debt, fiscal adjustment and social-sector financing in Ethiopia.',
    'remote','external','Open UNICEF Careers and apply to vacancy #595328 before the official deadline.',now(),
    'official_external','https://jobs.unicef.org/en-us/search/?search-keyword=ethiopia',now(),v_admin,
    'Official UNICEF Careers current vacancy verified as re-advertised with 11 October 2026 deadline.',now(),'approved',
    'Official UNICEF source verified for launch catalog.',v_admin,now()
  where not exists(select 1 from public.opportunities where title='Senior Economic & Public Finance Consultant — UNICEF Ethiopia #595328');

  insert into public.opportunities(
    posted_by,title,description,organization,location,is_remote,external_url,deadline,status,
    organization_name,sector_category,opportunity_type,employment_type_label,stipend_or_reward,
    requirements,verified_source,skills_required,experience_level,education_level,summary,
    work_arrangement,application_method,application_instructions,published_at,source_type,source_url,
    source_verified_at,source_verified_by,source_notes,source_last_checked_at,moderation_status,
    moderation_notes,reviewed_by,reviewed_at
  )
  select v_admin,'Procurement Services Manager (P-4) — UNICEF Supply Division #00021902',
    'UNICEF Supply Division fixed-term Procurement Services Manager role responsible for identifying and executing procurement-service business transactions in collaboration with country offices and partners.',
    'UNICEF','Copenhagen, Denmark',false,
    'https://jobs.unicef.org/en-us/filter/?location=denmark&search-keyword=','2026-10-31','open',
    'UNICEF Supply Division','Manufacturing & Logistics'::public.launch_category,'jobs'::public.opportunity_type,
    'P-4 Fixed Term Appointment','UNICEF P-4 compensation and benefits; see official vacancy',
    array['Senior procurement/supply-chain or related experience appropriate to a P-4 role','Ability to manage procurement-service transactions and partner collaboration','See official UNICEF vacancy #00021902 for complete requirements'],
    'UNICEF Careers Denmark vacancies',array['Procurement','Supply chain','Partner management','Business transactions'],'Senior','Advanced professional qualification',
    'UNICEF Supply Division procurement-services leadership role in Copenhagen.',
    'onsite','external','Open the official UNICEF Denmark vacancies page and apply to vacancy #00021902 before the deadline.',now(),
    'official_external','https://jobs.unicef.org/en-us/filter/?location=denmark&search-keyword=',now(),v_admin,
    'Official UNICEF Careers Denmark page verified vacancy #00021902 with 31 October 2026 deadline.',now(),'approved',
    'Official UNICEF source verified for launch catalog.',v_admin,now()
  where not exists(select 1 from public.opportunities where title='Procurement Services Manager (P-4) — UNICEF Supply Division #00021902');
end
$migration$;
;

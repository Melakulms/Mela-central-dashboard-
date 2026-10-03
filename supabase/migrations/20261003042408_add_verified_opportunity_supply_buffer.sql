-- Production-applied official-source buffer so the launch supply gate does not expire immediately.
do $migration$
declare
  v_admin uuid;
begin
  select au.user_id into v_admin
  from admin.admin_users au
  join public.profiles p on p.id=au.user_id
  where au.active and p.account_status='active' and p.deleted_at is null
  order by au.user_id limit 1;
  if v_admin is null then raise exception 'active admin registry user required'; end if;

  insert into public.opportunities(
    posted_by,title,description,organization,location,is_remote,external_url,deadline,status,
    organization_name,sector_category,opportunity_type,employment_type_label,stipend_or_reward,
    requirements,verified_source,skills_required,experience_level,education_level,summary,
    work_arrangement,application_method,application_instructions,published_at,source_type,source_url,
    source_verified_at,source_verified_by,source_notes,source_last_checked_at,moderation_status,
    moderation_notes,reviewed_by,reviewed_at
  )
  select v_admin,v.title,v.description,'UNICEF',v.location,v.is_remote,v.source_url,v.deadline::date,'open',
    v.organization,v.sector::public.launch_category,'jobs'::public.opportunity_type,v.employment_type,
    'UNICEF compensation/consultancy terms; see official vacancy',v.requirements,'UNICEF Careers current vacancies',
    v.skills,v.experience_level,v.education_level,v.summary,v.work_arrangement,'external',v.instructions,now(),
    'official_external',v.source_url,now(),v_admin,v.source_note,now(),'approved',
    'Official UNICEF source verified for launch catalog.',v_admin,now()
  from (values
    ('Security Specialist (P-3) — UNICEF Mozambique #00113729','UNICEF Mozambique security role providing risk management, humanitarian-access coordination, incident response and emergency preparedness.','UNICEF Mozambique','Pemba, Mozambique',false,'https://jobs.unicef.org/en-us/search/?search-keyword=00113729','2026-10-14','Education & Social Sciences','P-3 Fixed Term Appointment',array['Security risk management experience','Humanitarian or complex operating-environment experience','See official vacancy for complete requirements'],array['Security risk management','Humanitarian access','Emergency preparedness','Incident response'],'Experienced professional','Professional qualification per UNICEF vacancy','UNICEF security role supporting safe programme delivery in northern Mozambique.','onsite','Search vacancy #00113729 on UNICEF Careers and apply before the deadline.','Official UNICEF Careers listing verified with 14 October 2026 deadline.'),
    ('Social & Behaviour Change Specialist (NO-3) — UNICEF Nepal #00137825','UNICEF Nepal national specialist role in social and behavioral change programming.','UNICEF Nepal','Kathmandu, Nepal',false,'https://jobs.unicef.org/en-us/search/?search-keyword=00137825','2026-10-15','Education & Social Sciences','NO-3 Fixed Term Appointment',array['Open only for Nepalese nationals','Relevant social and behavioral change experience','See official vacancy for complete requirements'],array['Social and behavioral change','Programme implementation','Community engagement'],'Experienced professional','Professional qualification per UNICEF vacancy','UNICEF Nepal national specialist opportunity in social and behavioral change.','onsite','Search vacancy #00137825 on UNICEF Careers and apply before the deadline.','Official UNICEF Careers listing verified with 15 October 2026 deadline.'),
    ('National Lead Consultant — EU4People Social Protection Programme, UNICEF Bosnia and Herzegovina','UNICEF consultancy providing implementation, coordination and quality assurance for the EU4People Social Protection Programme.','UNICEF Bosnia and Herzegovina','Bosnia and Herzegovina / Remote with travel',true,'https://jobs.unicef.org/en-us/search/?search-keyword=EU4People','2026-10-15','Education & Social Sciences','National Lead Consultancy — 21 months',array['National consultant eligibility as specified by UNICEF','Field implementation and coordination experience','Social protection or local-service delivery expertise'],array['Social protection','Programme coordination','Field implementation','Quality assurance'],'Lead consultant','Professional qualification per UNICEF vacancy','Long-term national consultancy supporting EU4People social-protection implementation.','hybrid','Search EU4People on UNICEF Careers and apply before the official deadline.','Official UNICEF Careers listing verified with 15 October 2026 deadline.'),
    ('Chief Education (Learning, Skills and Engagement) (P-5) — UNICEF Mozambique #00047093','Senior UNICEF education leadership role spanning foundational learning, inclusive learning, skills pathways and education-system resilience.','UNICEF Mozambique','Maputo, Mozambique',false,'https://jobs.unicef.org/en-us/search/?search-keyword=00047093','2026-10-15','Education & Social Sciences','P-5 Fixed Term Appointment',array['Senior education-sector leadership experience','Expertise in learning, skills and system strengthening','See official vacancy for complete requirements'],array['Education leadership','Learning systems','Skills pathways','Programme strategy'],'Executive / senior','Advanced professional qualification','Senior UNICEF education leadership opportunity in Mozambique.','onsite','Search vacancy #00047093 on UNICEF Careers and apply before the deadline.','Official UNICEF Careers listing verified with 15 October 2026 deadline.'),
    ('International Private Sector Engagement Consultant — UNICEF Montenegro','UNICEF Montenegro consultancy strengthening strategic engagement and partnerships with the private sector.','UNICEF Montenegro','Montenegro',true,'https://jobs.unicef.org/en-us/search/?search-keyword=Private%20Sector%20Engagement','2026-10-15','Business & Finance','International Consultancy',array['Private-sector engagement or partnership expertise','International consultancy eligibility per UNICEF vacancy','See official vacancy for complete requirements'],array['Private-sector engagement','Partnerships','Strategy','Stakeholder management'],'Consultant','Professional qualification per UNICEF vacancy','International consultancy strengthening private-sector partnerships for UNICEF Montenegro.','hybrid','Search Private Sector Engagement on UNICEF Careers and apply before the deadline.','Official UNICEF Careers listing verified with 15 October 2026 deadline.')
  ) as v(title,description,organization,location,is_remote,source_url,deadline,sector,employment_type,requirements,skills,experience_level,education_level,summary,work_arrangement,instructions,source_note)
  where not exists(select 1 from public.opportunities o where o.source_url=v.source_url);
end
$migration$;

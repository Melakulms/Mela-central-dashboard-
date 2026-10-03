-- Replace stale legacy supply removed by the fixed freshness job with a current official-source route.
do $migration$
declare
  v_admin uuid;
begin
  select au.user_id into v_admin
  from admin.admin_users au
  join public.profiles p on p.id=au.user_id
  where au.active=true and p.account_status='active' and p.deleted_at is null
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
  select
    v_admin,
    'Gates Cambridge Scholarship route — MPhil Education, Globalisation and International Development 2027',
    'University of Cambridge MPhil in Education (Education, Globalisation and International Development) for Michaelmas 2027. The official course page states a course funding deadline of 8 December 2026 and provides the Gates Cambridge scholarship application requirements for eligible applicants.',
    'University of Cambridge','Cambridge, United Kingdom',false,
    'https://www.postgraduate.study.cam.ac.uk/courses/directory/ededmpegd/apply','2026-12-08','open',
    'University of Cambridge','Education & Social Sciences'::public.launch_category,'scholarships'::public.opportunity_type,
    'Postgraduate scholarship / course funding route','Gates Cambridge full-cost scholarship for eligible awardees; see official Cambridge funding information',
    array['Apply to the MPhil in Education (Education, Globalisation and International Development)','Submit the complete application by the 8 December 2026 course funding deadline','Eligible Gates Cambridge applicants must provide the required Gates Cambridge reference and any applicable scholarship materials'],
    'University of Cambridge Postgraduate Study',array['Education','Development studies','Academic excellence','Leadership'],null,'Bachelor degree / MPhil entry',
    'Official Cambridge 2027 postgraduate course funding route with Gates Cambridge consideration for eligible applicants.',
    'onsite','external','Apply through the University of Cambridge Postgraduate Applicant Portal and meet the course funding deadline.',now(),
    'official_external','https://www.postgraduate.study.cam.ac.uk/courses/directory/ededmpegd/apply',now(),v_admin,
    'Official University of Cambridge course page verified with 8 December 2026 course funding deadline.',now(),'approved',
    'Official university source verified for launch catalog.',v_admin,now()
  where not exists (
    select 1 from public.opportunities
    where source_url='https://www.postgraduate.study.cam.ac.uk/courses/directory/ededmpegd/apply'
  );
end
$migration$;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814180718
create or replace function public.get_my_audience_context() returns jsonb language sql stable security invoker set search_path to '' as $function$
with me as(
 select p.*,s.audience_group,s.title stage_title,s.subtitle stage_subtitle,s.school_stage
 from public.profiles p left join public.education_audience_stages s on s.stage_key=p.education_stage_key
 where p.id=(select auth.uid())
),features as(
 select coalesce(jsonb_object_agg(m.feature_key,m.access_mode),'{}'::jsonb) j
 from me join public.audience_feature_matrix m on m.stage_key=me.education_stage_key
),opp_rules as(
 select coalesce(jsonb_object_agg(r.opportunity_type::text,r.access_mode),'{}'::jsonb) j
 from me join public.audience_opportunity_rules r on r.stage_key=me.education_stage_key
),sections as(
 select coalesce(jsonb_agg(jsonb_build_object('section_key',x.section_key,'title',x.title,'description',x.description,'display_order',x.display_order,'subsections',x.subsections) order by x.display_order),'[]'::jsonb) j
 from(
  select s.section_key,s.title,s.description,s.display_order,
   coalesce(jsonb_agg(jsonb_build_object('subsection_key',ss.subsection_key,'title',ss.title,'description',ss.description,'route_key',ss.route_key,'display_order',ss.display_order) order by ss.display_order) filter(where ss.subsection_key is not null),'[]'::jsonb) subsections
  from me
  join public.platform_audience_sections s on s.audience_group=case when me.audience_group='school' then 'school' when me.audience_group='higher_education' then 'higher_education' else 'school' end and s.active
  left join public.platform_audience_subsections ss on ss.section_key=s.section_key and ss.active and me.education_stage_key=any(ss.target_stages)
  group by s.section_key,s.title,s.description,s.display_order
  having count(ss.subsection_key)>0
 )x
)
select jsonb_build_object('role',me.role,'audience_group',me.audience_group,'stage_key',me.education_stage_key,'stage_title',me.stage_title,'stage_subtitle',me.stage_subtitle,'grade_level',me.grade_level,'institution_name',coalesce(me.institution_name,me.school_name,me.university),'safety_status',me.learner_safety_status,'onboarding_completed',me.education_onboarding_completed,'features',(select j from features),'opportunity_rules',(select j from opp_rules),'sections',(select j from sections)) from me;
$function$;

create or replace function public.refresh_my_school_safety_status() returns text language plpgsql security invoker set search_path to '' as $function$
declare v_uid uuid:=(select auth.uid());v_stage text;v_status text;begin
 if v_uid is null then raise exception 'authentication required';end if;
 select education_stage_key,learner_safety_status into v_stage,v_status from public.profiles where id=v_uid and role='student';
 if v_stage is null then raise exception 'education stage required';end if;
 if v_stage not like 'school_%' then return 'not_applicable';end if;
 if exists(select 1 from public.guardian_relationships g where g.learner_id=v_uid and g.status='verified') then
  update public.profiles set learner_safety_status='guardian_verified',updated_at=now() where id=v_uid;return 'guardian_verified';
 end if;
 if v_stage='school_11_12' and private.user_has_adult_work_attestation(v_uid) then
  update public.profiles set learner_safety_status='adult_self_attested',updated_at=now() where id=v_uid;return 'adult_self_attested';
 end if;
 update public.profiles set learner_safety_status='guardian_required',updated_at=now() where id=v_uid;return 'guardian_required';
end;$function$;
grant execute on function public.refresh_my_school_safety_status() to authenticated;
;

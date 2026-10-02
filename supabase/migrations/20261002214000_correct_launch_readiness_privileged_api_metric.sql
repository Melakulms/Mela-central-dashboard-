-- Production-applied readiness correction.
-- Intentional public certificate verification is allowlisted; the launch gate now
-- blocks only unreviewed anonymous SECURITY DEFINER exposure rather than every
-- authenticated privileged API wrapper.

create or replace function private.get_platform_launch_readiness()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=(select auth.uid());
  v_items jsonb;
  v_required int;
  v_satisfied int;
  v_real_employers int;
  v_real_opps int;
  v_real_tasks int;
  v_real_scholarships int;
  v_translated_certified int;
  v_public_tables int;
  v_rls_tables int;
  v_unreviewed_anon_definers int;
  v_allowlisted_anon_definers int;
begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;

  select count(*) into v_real_employers from public.employers e join public.profiles p on p.id=e.owner_id where e.verified=true and e.verification_status='verified' and coalesce(p.email,'') not like '%@mela.invalid';
  select count(*) into v_real_opps from public.opportunities o left join public.profiles p on p.id=o.posted_by where o.status='open' and o.verified_active=true and coalesce(p.email,'') not like '%@mela.invalid';
  select count(*) into v_real_tasks from public.marketplace_tasks t left join public.profiles p on p.id=t.posted_by where t.status='open' and coalesce(p.email,'') not like '%@mela.invalid';
  select count(*) into v_real_scholarships from public.opportunities o left join public.profiles p on p.id=o.posted_by where o.opportunity_type='scholarships'::public.opportunity_type and o.status='open' and o.verified_active=true and coalesce(p.email,'') not like '%@mela.invalid';
  select count(*) into v_translated_certified from public.assessment_language_certifications c where c.language_code in ('am','om','ti','so') and c.status='certified';

  select count(*)::int,count(*) filter(where c.relrowsecurity)::int into v_public_tables,v_rls_tables
  from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r';

  select
    count(*) filter(where not (p.proname='verify_course_certificate' and pg_catalog.pg_get_function_identity_arguments(p.oid)='p_certificate_code text'))::int,
    count(*) filter(where (p.proname='verify_course_certificate' and pg_catalog.pg_get_function_identity_arguments(p.oid)='p_certificate_code text'))::int
  into v_unreviewed_anon_definers,v_allowlisted_anon_definers
  from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prosecdef and has_function_privilege('anon',p.oid,'EXECUTE');

  with derived as (
    select r.*,
      case r.requirement_key
        when 'assessment_translation_certification' then case when v_translated_certified>=32 then 'complete' else 'pending' end
        when 'real_employer_supply' then case when v_real_employers>=3 then 'complete' else 'pending' end
        when 'real_opportunity_supply' then case when v_real_opps>=10 then 'complete' else 'pending' end
        when 'real_freelance_supply' then case when v_real_tasks>=5 then 'complete' else 'pending' end
        when 'real_scholarship_supply' then case when v_real_scholarships>=5 then 'complete' else 'pending' end
        when 'rls_all_public' then case when v_public_tables=v_rls_tables then 'complete' else 'blocked' end
        when 'no_public_security_definers' then case when v_unreviewed_anon_definers=0 then 'complete' else 'blocked' end
        when 'payments_provider' then case when not public.platform_feature_available('payments') then 'not_required' else r.manual_status end
        when 'payout_provider' then case when not public.platform_feature_available('payouts') then 'not_required' else r.manual_status end
        when 'video_provider' then case when not public.platform_feature_available('video_calls') then 'not_required' else r.manual_status end
        else r.manual_status
      end as derived_status,
      case r.requirement_key
        when 'assessment_translation_certification' then jsonb_build_object('certified',v_translated_certified,'required',32)
        when 'real_employer_supply' then jsonb_build_object('current',v_real_employers,'required',3)
        when 'real_opportunity_supply' then jsonb_build_object('current',v_real_opps,'required',10)
        when 'real_freelance_supply' then jsonb_build_object('current',v_real_tasks,'required',5)
        when 'real_scholarship_supply' then jsonb_build_object('current',v_real_scholarships,'required',5)
        when 'rls_all_public' then jsonb_build_object('public_tables',v_public_tables,'rls_enabled',v_rls_tables)
        when 'no_public_security_definers' then jsonb_build_object('unreviewed_anonymous_exposure',v_unreviewed_anon_definers,'allowlisted_public_verifiers',v_allowlisted_anon_definers)
        else '{}'::jsonb
      end as metrics
    from public.platform_launch_requirements r
  ), counts as (
    select count(*) filter(where required)::int required_count,
           count(*) filter(where required and derived_status in ('complete','not_required'))::int satisfied_count
    from derived
  )
  select jsonb_agg(jsonb_build_object(
      'requirement_key',requirement_key,'category',category,'title',title,'requirement_type',requirement_type,'required',required,
      'status',derived_status,'evidence_note',evidence_note,'evidence_url',evidence_url,'completed_by',completed_by,'completed_at',completed_at,'metrics',metrics
    ) order by category,title),
    (select required_count from counts),(select satisfied_count from counts)
  into v_items,v_required,v_satisfied
  from derived;

  return jsonb_build_object(
    'decision',case when v_required=v_satisfied then 'GO' else 'NO_GO' end,
    'required',v_required,'satisfied',v_satisfied,'remaining',v_required-v_satisfied,
    'items',coalesce(v_items,'[]'::jsonb),'computed_at',now()
  );
end $function$;

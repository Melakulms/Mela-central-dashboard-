-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260816233113
create or replace function private.refresh_opportunity_candidate_matches_system(p_opportunity_id uuid, p_updated_by uuid default null)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare
  v_opp public.opportunities%rowtype;
  v_cfg public.opportunity_matching_configs%rowtype;
  v_count integer := 0;
begin
  select * into v_opp from public.opportunities where id=p_opportunity_id;
  if not found or v_opp.employer_id is null then return 0; end if;
  if v_opp.status <> 'open' or coalesce(v_opp.verified_active,false) is not true then return 0; end if;

  select * into v_cfg from public.opportunity_matching_configs where opportunity_id=p_opportunity_id;
  if not found then
    insert into public.opportunity_matching_configs(opportunity_id,updated_by)
    values(p_opportunity_id,p_updated_by)
    on conflict (opportunity_id) do nothing;
    select * into v_cfg from public.opportunity_matching_configs where opportunity_id=p_opportunity_id;
  end if;

  with applicants as (
    select a.applicant_id candidate_id,p.university,p.major,p.gpa,
      coalesce(array_agg(distinct vs.skill_name) filter (where vs.verified=true),'{}'::text[]) verified_skill_names,
      count(*) filter (where vs.verified=true) verified_skill_count
    from public.applications a
    join public.profiles p on p.id=a.applicant_id
    left join public.verified_skills vs on vs.user_id=a.applicant_id
    where a.opportunity_id=p_opportunity_id and a.status not in ('withdrawn','rejected')
    group by a.applicant_id,p.university,p.major,p.gpa
  ), scored as (
    select ap.*,
      coalesce((select array_agg(req) from unnest(v_opp.skills_required) req where req=any(ap.verified_skill_names)),'{}'::text[]) matched_skills,
      coalesce((select array_agg(req) from unnest(v_opp.skills_required) req where not(req=any(ap.verified_skill_names))),'{}'::text[]) missing_skills,
      case when coalesce(array_length(v_opp.skills_required,1),0)=0 then 100::numeric else
        100::numeric*coalesce((select count(*) from unnest(v_opp.skills_required) req where req=any(ap.verified_skill_names)),0)/array_length(v_opp.skills_required,1) end skill_score,
      case when v_cfg.minimum_gpa is not null and (ap.gpa is null or ap.gpa<v_cfg.minimum_gpa) then 0::numeric
           when coalesce(array_length(v_cfg.preferred_majors,1),0)>0 and ap.major=any(v_cfg.preferred_majors) then 100::numeric
           when coalesce(array_length(v_cfg.preferred_universities,1),0)>0 and ap.university=any(v_cfg.preferred_universities) then 100::numeric
           else 75::numeric end education_score,
      case when ap.verified_skill_count>0 then 100::numeric else 0::numeric end verified_score,
      case when lower(coalesce(v_opp.experience_level,'')) like '%entry%' then 100::numeric else 70::numeric end experience_score
    from applicants ap
  ), final_scores as (
    select s.*,
      round((s.skill_score*v_cfg.skills_weight+s.education_score*v_cfg.education_weight+s.experience_score*v_cfg.experience_weight+s.verified_score*v_cfg.verified_skills_weight)
        /nullif(v_cfg.skills_weight+v_cfg.education_weight+v_cfg.experience_weight+v_cfg.verified_skills_weight,0),2) final_score
    from scored s
  )
  insert into public.candidate_matches(employer_id,opportunity_id,candidate_id,match_score,matched_skills,missing_skills,reasons,status,generated_at)
  select v_opp.employer_id,p_opportunity_id,f.candidate_id,f.final_score,f.matched_skills,f.missing_skills,
    jsonb_build_array(
      jsonb_build_object('factor','skills','score',round(f.skill_score,2)),
      jsonb_build_object('factor','education','score',round(f.education_score,2)),
      jsonb_build_object('factor','experience','score',round(f.experience_score,2)),
      jsonb_build_object('factor','verified_skills','score',round(f.verified_score,2))
    ),case when f.final_score>=v_cfg.min_match_score then 'recommended' else 'below_threshold' end,now()
  from final_scores f
  on conflict (opportunity_id,candidate_id) do update set
    employer_id=excluded.employer_id,
    match_score=excluded.match_score,
    matched_skills=excluded.matched_skills,
    missing_skills=excluded.missing_skills,
    reasons=excluded.reasons,
    status=case when public.candidate_matches.status in ('saved','dismissed','contacted') then public.candidate_matches.status else excluded.status end,
    generated_at=excluded.generated_at;
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;
revoke all on function private.refresh_opportunity_candidate_matches_system(uuid,uuid) from public,anon,authenticated;

create or replace function private.refresh_opportunity_candidate_matches(p_opportunity_id uuid)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_opp public.opportunities%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_opp from public.opportunities where id=p_opportunity_id;
  if not found or v_opp.employer_id is null then raise exception 'opportunity not found'; end if;
  if not private.has_employer_access(v_opp.employer_id,true) then raise exception 'not authorized for this employer'; end if;
  return private.refresh_opportunity_candidate_matches_system(p_opportunity_id,v_uid);
end;
$$;

create or replace function private.match_refresh_on_opportunity()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.employer_id is null or new.status <> 'open' or coalesce(new.verified_active,false) is not true then
    return new;
  end if;
  perform private.refresh_opportunity_candidate_matches_system(new.id,(select auth.uid()));
  return new;
end;
$$;

create or replace function private.match_refresh_on_config()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if exists(select 1 from public.opportunities o where o.id=new.opportunity_id and o.employer_id is not null and o.status='open' and o.verified_active=true) then
    perform private.refresh_opportunity_candidate_matches_system(new.opportunity_id,(select auth.uid()));
  end if;
  return new;
end;
$$;

create or replace function private.refresh_matches_for_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare r record;
begin
  for r in
    select distinct a.opportunity_id
    from public.applications a
    join public.opportunities o on o.id=a.opportunity_id
    where a.applicant_id=p_user_id and o.employer_id is not null and o.status='open' and o.verified_active=true
  loop
    perform private.refresh_opportunity_candidate_matches_system(r.opportunity_id,(select auth.uid()));
  end loop;
end;
$$;
;

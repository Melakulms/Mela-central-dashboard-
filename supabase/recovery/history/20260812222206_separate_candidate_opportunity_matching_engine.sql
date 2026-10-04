-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812222206
create or replace function private.refresh_my_opportunity_matches()
returns integer
language plpgsql security definer set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_profile public.profiles%rowtype;
  v_skills text[] := '{}';
  v_verified_count integer := 0;
  r record;
  v_matched text[];
  v_missing text[];
  v_skill_score numeric;
  v_education_score numeric;
  v_experience_score numeric;
  v_verified_score numeric;
  v_final numeric;
  v_has_must boolean;
  v_count integer := 0;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_profile from public.profiles where id=v_uid;
  if not found or v_profile.role<>'student'::public.user_role then raise exception 'student/talent profile required'; end if;

  select coalesce(array_agg(distinct lower(skill_name)) filter(where verified=true),'{}'::text[]),count(*) filter(where verified=true)
    into v_skills,v_verified_count from public.verified_skills where user_id=v_uid;

  -- Remove stale auto-generated recommendations while preserving employer-curated states.
  delete from public.candidate_matches m
   where m.candidate_id=v_uid and m.status in ('recommended','below_threshold')
     and (m.opportunity_id is null or not exists(
       select 1 from public.opportunities o where o.id=m.opportunity_id and o.status='open' and o.verified_active=true and o.deadline>=current_date
     ));

  for r in
    select o.*,
           coalesce(c.min_match_score,60) min_match_score,
           coalesce(c.skills_weight,50) skills_weight,
           coalesce(c.education_weight,15) education_weight,
           coalesce(c.experience_weight,20) experience_weight,
           coalesce(c.verified_skills_weight,15) verified_skills_weight,
           coalesce(c.must_have_skills,'{}'::text[]) must_have_skills,
           coalesce(c.preferred_universities,'{}'::text[]) preferred_universities,
           coalesce(c.preferred_majors,'{}'::text[]) preferred_majors,
           c.minimum_gpa
      from public.opportunities o
      left join public.opportunity_matching_configs c on c.opportunity_id=o.id
     where o.status='open' and o.verified_active=true and o.deadline>=current_date and o.employer_id is not null
  loop
    select coalesce(array_agg(req),'{}'::text[]) into v_matched
      from unnest(coalesce(r.skills_required,'{}'::text[])) req
     where lower(req)=any(v_skills);
    select coalesce(array_agg(req),'{}'::text[]) into v_missing
      from unnest(coalesce(r.skills_required,'{}'::text[])) req
     where not(lower(req)=any(v_skills));

    v_skill_score:=case when coalesce(array_length(r.skills_required,1),0)=0 then 100
      else round(100.0*coalesce(array_length(v_matched,1),0)/array_length(r.skills_required,1),2) end;
    v_education_score:=case
      when r.minimum_gpa is not null and (v_profile.gpa is null or v_profile.gpa<r.minimum_gpa) then 0
      when coalesce(array_length(r.preferred_majors,1),0)>0 and v_profile.major is not null and exists(select 1 from unnest(r.preferred_majors) x where lower(x)=lower(v_profile.major) or lower(v_profile.major) like '%'||lower(x)||'%') then 100
      when coalesce(array_length(r.preferred_universities,1),0)>0 and v_profile.university is not null and exists(select 1 from unnest(r.preferred_universities) x where lower(x)=lower(v_profile.university)) then 100
      else 75 end;
    v_experience_score:=case when lower(coalesce(r.experience_level,'')) like '%entry%' or lower(coalesce(r.experience_level,'')) like '%junior%' or coalesce(r.experience_level,'')='' then 100 else 70 end;
    v_verified_score:=case when v_verified_count>0 then 100 else 0 end;
    v_has_must:=not exists(select 1 from unnest(r.must_have_skills) x where not(lower(x)=any(v_skills)));
    v_final:=round((v_skill_score*r.skills_weight+v_education_score*r.education_weight+v_experience_score*r.experience_weight+v_verified_score*r.verified_skills_weight)
      /nullif(r.skills_weight+r.education_weight+r.experience_weight+r.verified_skills_weight,0),2);
    if not v_has_must then v_final:=least(v_final,40); end if;

    insert into public.candidate_matches(employer_id,opportunity_id,candidate_id,match_score,matched_skills,missing_skills,reasons,status,generated_at)
    values(r.employer_id,r.id,v_uid,v_final,v_matched,v_missing,
      jsonb_build_array(
        jsonb_build_object('factor','skills','score',v_skill_score),
        jsonb_build_object('factor','education','score',v_education_score),
        jsonb_build_object('factor','experience','score',v_experience_score),
        jsonb_build_object('factor','verified_skills','score',v_verified_score),
        jsonb_build_object('factor','must_have_skills','passed',v_has_must)
      ),case when v_final>=r.min_match_score and v_has_must then 'recommended' else 'below_threshold' end,now())
    on conflict(opportunity_id,candidate_id) do update set
      employer_id=excluded.employer_id,match_score=excluded.match_score,matched_skills=excluded.matched_skills,missing_skills=excluded.missing_skills,reasons=excluded.reasons,
      status=case when public.candidate_matches.status in ('saved','dismissed','contacted') then public.candidate_matches.status else excluded.status end,generated_at=now();
    v_count:=v_count+1;
  end loop;
  return v_count;
end $$;

create or replace function public.refresh_my_opportunity_matches()
returns integer language sql security invoker set search_path=''
as $$ select private.refresh_my_opportunity_matches(); $$;

revoke all on function private.refresh_my_opportunity_matches() from public,anon;
grant execute on function private.refresh_my_opportunity_matches() to authenticated,service_role;
revoke all on function public.refresh_my_opportunity_matches() from public,anon;
grant execute on function public.refresh_my_opportunity_matches() to authenticated,service_role;
;

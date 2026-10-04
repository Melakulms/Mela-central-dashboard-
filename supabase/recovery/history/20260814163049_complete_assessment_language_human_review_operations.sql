-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814163049
create or replace function private.save_assessment_question_translation_review(
  p_question_id uuid,
  p_language_code text,
  p_prompt text,
  p_choices jsonb,
  p_competency text default null
)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=(select auth.uid());
  v_assessment uuid;
  v_source_version integer;
  v_source_choices jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if p_language_code not in ('am','om','ti','so') then raise exception 'unsupported translation language'; end if;
  select assessment_id,version,choices into v_assessment,v_source_version,v_source_choices
  from public.assessment_questions where id=p_question_id and active=true and language_code='en';
  if not found then raise exception 'source assessment question not found'; end if;
  if not exists(
    select 1 from public.assessment_language_review_assignments a
    join public.assessment_language_reviewer_qualifications q on q.reviewer_id=a.reviewer_id and q.language_code=a.language_code and q.qualified=true
    where a.assessment_id=v_assessment and a.language_code=p_language_code and a.reviewer_id=v_uid and a.status in ('assigned','in_review','approved','changes_required')
  ) and not private.is_admin_user() then raise exception 'qualified language review assignment required'; end if;
  if nullif(trim(coalesce(p_prompt,'')),'') is null then raise exception 'translated prompt is required'; end if;
  if jsonb_typeof(p_choices)<>'array' or jsonb_array_length(p_choices)<>jsonb_array_length(v_source_choices) then raise exception 'translated choices must preserve the source choice count'; end if;
  if exists(
    select 1 from jsonb_array_elements(p_choices) c
    where nullif(trim(coalesce(c->>'id','')),'') is null or nullif(trim(coalesce(c->>'text','')),'') is null
  ) then raise exception 'each translated choice needs id and text'; end if;
  if exists(
    select 1
    from jsonb_array_elements(v_source_choices) s
    left join jsonb_array_elements(p_choices) t on t->>'id'=s->>'id'
    where t is null
  ) then raise exception 'translated choice IDs must match the source choices'; end if;

  insert into public.assessment_question_translations(question_id,assessment_id,language_code,prompt,choices,competency,source_version,translation_version,status,updated_by,updated_at)
  values(p_question_id,v_assessment,p_language_code,trim(p_prompt),p_choices,nullif(trim(coalesce(p_competency,'')),''),v_source_version,1,'in_review',v_uid,now())
  on conflict(question_id,language_code) do update set
    prompt=excluded.prompt,
    choices=excluded.choices,
    competency=excluded.competency,
    source_version=v_source_version,
    translation_version=public.assessment_question_translations.translation_version+1,
    status='in_review',
    updated_by=v_uid,
    updated_at=now();

  update public.assessment_language_review_assignments
     set status=case when reviewer_id=v_uid then 'in_review' when status='approved' then 'in_review' else status end,
         reviewer_notes=case when status='approved' then 'Translation changed after this approval; re-review required.' else reviewer_notes end,
         submitted_at=case when status='approved' then null else submitted_at end,
         updated_at=now()
   where assessment_id=v_assessment and language_code=p_language_code and status<>'cancelled';

  update public.assessment_language_certifications
     set status='in_review',certified_at=null,reviewed_by=null,
         reviewer_notes='Translation content changed; certification requires fresh independent reviews.',
         certification_metadata='{}'::jsonb,updated_at=now()
   where assessment_id=v_assessment and language_code=p_language_code;
end $$;

create or replace function private.admin_get_assessment_language_review_status()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_result jsonb; begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
  select jsonb_build_object(
    'certifications',coalesce((select jsonb_agg(jsonb_build_object(
      'assessment_id',c.assessment_id,'assessment_title',a.title,'category',a.category,'language_code',c.language_code,'status',c.status,
      'reviewer_notes',c.reviewer_notes,'certified_at',c.certified_at,'certification_metadata',c.certification_metadata,
      'translation_count',(select count(*) from public.assessment_question_translations t where t.assessment_id=c.assessment_id and t.language_code=c.language_code),
      'source_count',(select count(*) from public.assessment_questions q where q.assessment_id=c.assessment_id and q.active=true and q.language_code='en'),
      'approved_reviews',(select count(distinct r.reviewer_id) from public.assessment_language_review_assignments r join public.assessment_language_reviewer_qualifications rq on rq.reviewer_id=r.reviewer_id and rq.language_code=r.language_code and rq.qualified=true where r.assessment_id=c.assessment_id and r.language_code=c.language_code and r.status='approved')
    ) order by a.title,c.language_code) from public.assessment_language_certifications c join public.skill_assessments a on a.id=c.assessment_id),'[]'::jsonb),
    'qualifications',coalesce((select jsonb_agg(jsonb_build_object('reviewer_id',q.reviewer_id,'full_name',p.full_name,'email',p.email,'language_code',q.language_code,'qualified',q.qualified,'qualification_notes',q.qualification_notes,'approved_at',q.approved_at) order by p.full_name,q.language_code) from public.assessment_language_reviewer_qualifications q join public.profiles p on p.id=q.reviewer_id),'[]'::jsonb),
    'assignments',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'assessment_id',r.assessment_id,'assessment_title',a.title,'language_code',r.language_code,'reviewer_id',r.reviewer_id,'reviewer_name',p.full_name,'reviewer_email',p.email,'status',r.status,'reviewer_notes',r.reviewer_notes,'assigned_at',r.assigned_at,'submitted_at',r.submitted_at) order by r.assigned_at desc) from public.assessment_language_review_assignments r join public.skill_assessments a on a.id=r.assessment_id join public.profiles p on p.id=r.reviewer_id),'[]'::jsonb),
    'candidate_reviewers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'email',p.email,'role',p.role) order by p.full_name) from public.profiles p where p.email is not null),'[]'::jsonb)
  ) into v_result;
  return v_result;
end $$;

create or replace function public.save_assessment_question_translation_review(p_question_id uuid,p_language_code text,p_prompt text,p_choices jsonb,p_competency text default null)
returns void language sql set search_path='' as $$ select private.save_assessment_question_translation_review(p_question_id,p_language_code,p_prompt,p_choices,p_competency); $$;
create or replace function public.admin_get_assessment_language_review_status()
returns jsonb language sql set search_path='' as $$ select private.admin_get_assessment_language_review_status(); $$;

revoke execute on function private.save_assessment_question_translation_review(uuid,text,text,jsonb,text) from public,anon;
revoke execute on function private.admin_get_assessment_language_review_status() from public,anon;
grant execute on function private.save_assessment_question_translation_review(uuid,text,text,jsonb,text) to authenticated,service_role;
grant execute on function private.admin_get_assessment_language_review_status() to authenticated,service_role;
revoke execute on function public.save_assessment_question_translation_review(uuid,text,text,jsonb,text) from public,anon;
revoke execute on function public.admin_get_assessment_language_review_status() from public,anon;
grant execute on function public.save_assessment_question_translation_review(uuid,text,text,jsonb,text) to authenticated;
grant execute on function public.admin_get_assessment_language_review_status() to authenticated;

;

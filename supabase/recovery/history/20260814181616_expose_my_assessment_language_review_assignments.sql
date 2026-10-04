-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814181616
create or replace function public.get_my_assessment_language_review_assignments()
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,
    'assessment_id',a.assessment_id,
    'assessment_title',s.title,
    'category',s.category,
    'language_code',a.language_code,
    'status',a.status,
    'reviewer_notes',a.reviewer_notes,
    'assigned_at',a.assigned_at,
    'submitted_at',a.submitted_at
  ) order by a.assigned_at desc),'[]'::jsonb)
  from public.assessment_language_review_assignments a
  join public.skill_assessments s on s.id=a.assessment_id
  where a.reviewer_id=(select auth.uid()) and a.status<>'cancelled';
$function$;
grant execute on function public.get_my_assessment_language_review_assignments() to authenticated;
;

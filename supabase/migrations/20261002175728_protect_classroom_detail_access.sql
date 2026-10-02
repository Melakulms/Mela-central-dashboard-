-- Authorize the entire response before reading a classroom roster.
create or replace function public.get_my_classroom_detail(p_classroom_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare v_uid uuid := (select auth.uid());
begin
 if v_uid is null or not coalesce(private.can_view_classroom(p_classroom_id,v_uid),false) then
  raise exception 'Classroom access denied' using errcode='42501';
 end if;
 return jsonb_build_object(
  'classroom',(select to_jsonb(c) from public.educator_classrooms c where c.id=p_classroom_id),
  'learners',coalesce((select jsonb_agg(jsonb_build_object(
   'id',p.id,'full_name',p.full_name,'stage_key',p.education_stage_key,
   'grade_level',p.grade_level,'institution_name',p.institution_name,
   'mastery',(select jsonb_build_object('overall_score',round(avg(mr.mastery_score),2),'evidence_count',coalesce(sum(mr.evidence_count),0))
    from public.learner_mastery_records mr where mr.user_id=p.id)
  ) order by p.full_name) from public.educator_classroom_members m
   join public.profiles p on p.id=m.learner_id
   where m.classroom_id=p_classroom_id and m.status='active'),'[]'::jsonb)
 );
end;
$function$;

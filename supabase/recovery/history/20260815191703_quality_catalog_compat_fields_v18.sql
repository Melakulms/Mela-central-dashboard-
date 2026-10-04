-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815191703
create or replace function private.get_question_catalog_v18(p_grade_level smallint default null)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  return jsonb_build_object(
    'quality_version','v18',
    'mastery_rule','deterministic_validated_or_educator_verified',
    'grades',coalesce((
      select jsonb_agg(jsonb_build_object(
        'grade_level',g.grade_level,
        'total_questions',g.total_questions,
        'mastery_questions',g.mastery_questions,
        'review_required_questions',g.review_required_questions,
        'free_questions',g.free_questions,
        'subscription_questions',g.subscription_questions,
        'paid_pack_questions',g.paid_pack_questions,
        'free_mastery_questions',g.free_mastery_questions,
        'subscription_mastery_questions',g.subscription_mastery_questions,
        'paid_pack_mastery_questions',g.paid_pack_mastery_questions,
        'subjects',g.subjects
      ) order by g.grade_level)
      from (
        select p.grade_level,
          sum(x.total_n)::bigint as total_questions,
          sum(x.mastery_n)::bigint as mastery_questions,
          sum(x.review_n)::bigint as review_required_questions,
          sum(x.free_n)::bigint as free_questions,
          sum(x.sub_n)::bigint as subscription_questions,
          sum(x.one_n)::bigint as paid_pack_questions,
          sum(x.free_mastery_n)::bigint as free_mastery_questions,
          sum(x.sub_mastery_n)::bigint as subscription_mastery_questions,
          sum(x.one_mastery_n)::bigint as paid_pack_mastery_questions,
          jsonb_agg(jsonb_build_object(
            'program_key',p.program_key,
            'track_key',p.track_key,
            'subject_key',p.subject_key,
            'subject_title',p.subject_title,
            'question_count',x.total_n,
            'mastery_count',x.mastery_n,
            'review_required_count',x.review_n,
            'mastery_needed_for_500',greatest(500-x.mastery_n,0),
            'free_count',x.free_n,
            'subscription_count',x.sub_n,
            'paid_pack_count',x.one_n,
            'free_mastery_count',x.free_mastery_n,
            'subscription_mastery_count',x.sub_mastery_n,
            'paid_pack_mastery_count',x.one_mastery_n,
            'chapter_count',(select count(*) from public.mela_learning_chapters c where c.program_key=p.program_key and c.status='published'),
            'topic_count',(select count(*) from public.mela_learning_chapter_topics t join public.mela_learning_chapters c2 on c2.id=t.chapter_id where c2.program_key=p.program_key and t.status='published')
          ) order by p.display_order,p.subject_title,p.track_key) as subjects
        from public.mela_learning_programs p
        join lateral (
          select count(*)::int as total_n,
            count(*) filter(where q.validation_status in ('deterministic_validated','educator_verified'))::int as mastery_n,
            count(*) filter(where q.validation_status='review_required')::int as review_n,
            count(*) filter(where q.access_tier='free')::int as free_n,
            count(*) filter(where q.access_tier='subscription')::int as sub_n,
            count(*) filter(where q.access_tier='one_time')::int as one_n,
            count(*) filter(where q.access_tier='free' and q.validation_status in ('deterministic_validated','educator_verified'))::int as free_mastery_n,
            count(*) filter(where q.access_tier='subscription' and q.validation_status in ('deterministic_validated','educator_verified'))::int as sub_mastery_n,
            count(*) filter(where q.access_tier='one_time' and q.validation_status in ('deterministic_validated','educator_verified'))::int as one_mastery_n
          from public.mela_question_bank q where q.program_key=p.program_key and q.active
        ) x on true
        where p.program_kind='school_subject' and p.grade_level between 1 and 12 and p.active
          and (p_grade_level is null or p.grade_level=p_grade_level)
        group by p.grade_level
      ) g
    ),'[]'::jsonb)
  );
end;
$$;
;

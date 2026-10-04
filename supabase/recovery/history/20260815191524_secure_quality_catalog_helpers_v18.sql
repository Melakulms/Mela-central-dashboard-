-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815191524
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
        'subjects',g.subjects
      ) order by g.grade_level)
      from (
        select p.grade_level,
          sum(x.total_n)::bigint as total_questions,
          sum(x.mastery_n)::bigint as mastery_questions,
          sum(x.review_n)::bigint as review_required_questions,
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
          from public.mela_question_bank q
          where q.program_key=p.program_key and q.active
        ) x on true
        where p.program_kind='school_subject' and p.grade_level between 1 and 12 and p.active
          and (p_grade_level is null or p.grade_level=p_grade_level)
        group by p.grade_level
      ) g
    ),'[]'::jsonb)
  );
end;
$$;
revoke all on function private.get_question_catalog_v18(smallint) from public, anon;
grant execute on function private.get_question_catalog_v18(smallint) to authenticated;

create or replace function public.get_question_catalog_v18(p_grade_level smallint default null)
returns jsonb
language sql
stable
set search_path=''
as $$ select private.get_question_catalog_v18(p_grade_level); $$;
revoke all on function public.get_question_catalog_v18(smallint) from public, anon;
grant execute on function public.get_question_catalog_v18(smallint) to authenticated;

create or replace function private.get_question_subject_detail_v18(p_program_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_program public.mela_learning_programs%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_program from public.mela_learning_programs
  where program_key=p_program_key and active and program_kind='school_subject' and grade_level between 1 and 12;
  if not found then raise exception 'program not found'; end if;
  return jsonb_build_object(
    'quality_version','v18',
    'program',jsonb_build_object(
      'program_key',v_program.program_key,'grade_level',v_program.grade_level,'track_key',v_program.track_key,
      'subject_key',v_program.subject_key,'subject_title',v_program.subject_title,
      'question_count',(select count(*) from public.mela_question_bank q where q.program_key=v_program.program_key and q.active),
      'mastery_count',(select count(*) from public.mela_question_bank q where q.program_key=v_program.program_key and q.active and q.validation_status in ('deterministic_validated','educator_verified')),
      'review_required_count',(select count(*) from public.mela_question_bank q where q.program_key=v_program.program_key and q.active and q.validation_status='review_required')
    ),
    'chapters',coalesce((
      select jsonb_agg(jsonb_build_object(
        'chapter_id',c.id,'chapter_number',c.chapter_number,'chapter_title',c.title,
        'question_count',coalesce(qc.total_n,0),'mastery_count',coalesce(qc.mastery_n,0),'review_required_count',coalesce(qc.review_n,0),
        'free_count',coalesce(qc.free_n,0),'subscription_count',coalesce(qc.sub_n,0),'paid_pack_count',coalesce(qc.one_n,0),
        'topics',coalesce((
          select jsonb_agg(jsonb_build_object(
            'topic_id',t.id,'topic_number',t.topic_number,'topic_title',t.title,
            'question_count',coalesce(tq.total_n,0),'mastery_count',coalesce(tq.mastery_n,0),'review_required_count',coalesce(tq.review_n,0),
            'free_count',coalesce(tq.free_n,0),'subscription_count',coalesce(tq.sub_n,0),'paid_pack_count',coalesce(tq.one_n,0)
          ) order by t.display_order,t.topic_number)
          from public.mela_learning_chapter_topics t
          left join lateral (
            select count(*)::int as total_n,
              count(*) filter(where q.validation_status in ('deterministic_validated','educator_verified'))::int as mastery_n,
              count(*) filter(where q.validation_status='review_required')::int as review_n,
              count(*) filter(where q.access_tier='free')::int as free_n,
              count(*) filter(where q.access_tier='subscription')::int as sub_n,
              count(*) filter(where q.access_tier='one_time')::int as one_n
            from public.mela_question_bank q where q.topic_id=t.id and q.active
          ) tq on true
          where t.chapter_id=c.id and t.status='published'
        ),'[]'::jsonb)
      ) order by c.display_order,c.chapter_number)
      from public.mela_learning_chapters c
      left join lateral (
        select count(*)::int as total_n,
          count(*) filter(where q.validation_status in ('deterministic_validated','educator_verified'))::int as mastery_n,
          count(*) filter(where q.validation_status='review_required')::int as review_n,
          count(*) filter(where q.access_tier='free')::int as free_n,
          count(*) filter(where q.access_tier='subscription')::int as sub_n,
          count(*) filter(where q.access_tier='one_time')::int as one_n
        from public.mela_question_bank q where q.chapter_id=c.id and q.active
      ) qc on true
      where c.program_key=p_program_key and c.status='published'
    ),'[]'::jsonb)
  );
end;
$$;
revoke all on function private.get_question_subject_detail_v18(text) from public, anon;
grant execute on function private.get_question_subject_detail_v18(text) to authenticated;

create or replace function public.get_question_subject_detail_v18(p_program_key text)
returns jsonb
language sql
stable
set search_path=''
as $$ select private.get_question_subject_detail_v18(p_program_key); $$;
revoke all on function public.get_question_subject_detail_v18(text) from public, anon;
grant execute on function public.get_question_subject_detail_v18(text) to authenticated;
;

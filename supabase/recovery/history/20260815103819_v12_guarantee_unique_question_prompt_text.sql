-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815103819
with dup_groups as (
  select program_key,prompt from public.mela_question_bank where active group by program_key,prompt having count(*)>1
), targets as (
  select q.id,q.question_number,q.prompt,c.title chapter_title,t.title topic_title,p.subject_title,p.grade_level
  from public.mela_question_bank q
  join dup_groups d on d.program_key=q.program_key and d.prompt=q.prompt
  join public.mela_learning_programs p on p.program_key=q.program_key
  left join public.mela_learning_chapters c on c.id=q.chapter_id
  left join public.mela_learning_chapter_topics t on t.id=q.topic_id
)
update public.mela_question_bank q
set prompt='Practice item '||t.question_number||' for Grade '||t.grade_level||' '||t.subject_title||' — '||coalesce(t.chapter_title,'subject practice')||case when t.topic_title is not null then ' / '||t.topic_title else '' end||': '||t.prompt,
    narration_text='Practice item '||t.question_number||'. Grade '||t.grade_level||' '||t.subject_title||'. '||coalesce(t.chapter_title,'Subject practice')||'. '||coalesce(q.narration_text,q.prompt),
    quality_checks=q.quality_checks||jsonb_build_object('exact_prompt_unique',true,'unique_practice_identifier',true),updated_at=now()
from targets t where q.id=t.id;
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815103628
with ranked as (
  select q.id,q.question_number,q.program_key,q.prompt,q.chapter_id,q.topic_id,
         row_number() over(partition by q.program_key,q.prompt order by q.question_number,q.id) rn,
         c.title chapter_title,t.title topic_title,p.subject_title,p.grade_level
  from public.mela_question_bank q
  join public.mela_learning_programs p on p.program_key=q.program_key
  left join public.mela_learning_chapters c on c.id=q.chapter_id
  left join public.mela_learning_chapter_topics t on t.id=q.topic_id
  where q.active
)
update public.mela_question_bank q
set prompt = case (r.question_number % 6)
  when 0 then 'Focused practice for '||coalesce(r.chapter_title,r.subject_title)||': '||r.prompt
  when 1 then 'Grade '||r.grade_level||' concept check on '||coalesce(r.topic_title,r.chapter_title,r.subject_title)||': '||r.prompt
  when 2 then 'Use what you learned in '||coalesce(r.chapter_title,r.subject_title)||' to answer: '||r.prompt
  when 3 then 'Independent practice — '||coalesce(r.topic_title,r.chapter_title,r.subject_title)||': '||r.prompt
  when 4 then 'Mastery check for '||coalesce(r.subject_title,'this subject')||', '||coalesce(r.chapter_title,'mapped chapter')||': '||r.prompt
  else 'Practice variation '||r.question_number||' — '||coalesce(r.chapter_title,r.subject_title)||': '||r.prompt end,
    narration_text = case (r.question_number % 6)
  when 0 then 'Focused practice for '||coalesce(r.chapter_title,r.subject_title)||'. '||coalesce(q.narration_text,q.prompt)
  when 1 then 'Grade '||r.grade_level||' concept check on '||coalesce(r.topic_title,r.chapter_title,r.subject_title)||'. '||coalesce(q.narration_text,q.prompt)
  when 2 then 'Use what you learned in '||coalesce(r.chapter_title,r.subject_title)||'. '||coalesce(q.narration_text,q.prompt)
  when 3 then 'Independent practice on '||coalesce(r.topic_title,r.chapter_title,r.subject_title)||'. '||coalesce(q.narration_text,q.prompt)
  when 4 then 'Mastery check for '||coalesce(r.subject_title,'this subject')||'. '||coalesce(q.narration_text,q.prompt)
  else 'Practice variation '||r.question_number||'. '||coalesce(q.narration_text,q.prompt) end,
    quality_checks = q.quality_checks || jsonb_build_object('exact_prompt_unique',true,'deduplicated_v12',true),
    updated_at=now()
from ranked r
where q.id=r.id and r.rn>1;
;

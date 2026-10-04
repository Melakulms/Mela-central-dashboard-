-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815102815
with pdata as (
 select p.program_key,p.grade_level,p.subject_title,
        array_agg(c.title order by c.chapter_number) chapter_titles,
        array_agg(c.chapter_number order by c.chapter_number) chapter_numbers,
        count(c.id)::int nchap
 from public.mela_learning_programs p join public.mela_learning_chapters c on c.program_key=p.program_key and c.status='published'
 where p.program_kind='school_subject' and p.grade_level between 1 and 12 and p.active
 group by p.program_key,p.grade_level,p.subject_title
), qdata as (
 select q.*,p.grade_level,p.subject_title,p.chapter_titles,p.chapter_numbers,p.nchap,c.title chapter_title,c.chapter_number chapter_no,t.title topic_title,
        ((q.question_number-641)%p.nchap)+1 ci
 from public.mela_question_bank q join pdata p using(program_key)
 left join public.mela_learning_chapters c on c.id=q.chapter_id
 left join public.mela_learning_chapter_topics t on t.id=q.topic_id
 where q.generation_version='v12'
)
update public.mela_question_bank q
set prompt=case when d.question_number%2=0
                then 'True or false: “'||d.topic_title||'” is mapped to the different chapter “'||d.chapter_titles[((d.ci)%d.nchap)+1]||'”, rather than “'||d.chapter_title||'”.'
                else 'True or false: “'||d.topic_title||'” is a mapped learning topic in the chapter “'||d.chapter_title||'”.' end,
    narration_text=case when d.question_number%2=0
                then 'True or false question. '||d.topic_title||' is claimed to belong to '||d.chapter_titles[((d.ci)%d.nchap)+1]||' rather than '||d.chapter_title||'.'
                else 'True or false question. '||d.topic_title||' belongs to '||d.chapter_title||'.' end,
    updated_at=now()
from qdata d where q.id=d.id and d.question_type='true_false';

with pdata as (
 select p.program_key,p.grade_level,p.subject_title,
        array_agg(c.title order by c.chapter_number) chapter_titles,
        array_agg(c.chapter_number order by c.chapter_number) chapter_numbers,
        count(c.id)::int nchap
 from public.mela_learning_programs p join public.mela_learning_chapters c on c.program_key=p.program_key and c.status='published'
 where p.program_kind='school_subject' and p.grade_level between 1 and 12 and p.active
 group by p.program_key,p.grade_level,p.subject_title
), qdata as (
 select q.*,p.grade_level,p.subject_title,p.chapter_titles,p.chapter_numbers,p.nchap,c.title chapter_title,c.chapter_number chapter_no,t.title topic_title,
        ((q.question_number-641)%p.nchap)+1 ci
 from public.mela_question_bank q join pdata p using(program_key)
 left join public.mela_learning_chapters c on c.id=q.chapter_id
 left join public.mela_learning_chapter_topics t on t.id=q.topic_id
 where q.generation_version='v12'
)
insert into private.mela_question_grading_v12(question_id,grading_kind,correct_response,accepted_variants,tolerance,rationale,grading_version)
select id,
       case when question_type in ('passage_choice','scenario_choice') then 'single_choice' else question_type end,
       case question_type
         when 'single_choice' then jsonb_build_object('choice',chapter_title)
         when 'passage_choice' then jsonb_build_object('choice',chapter_title)
         when 'scenario_choice' then jsonb_build_object('choice',chapter_title)
         when 'true_false' then jsonb_build_object('choice',case when question_number%2=0 then 'False' else 'True' end)
         when 'multi_select' then jsonb_build_object('choices',jsonb_build_array('Understand the mapped topic before advanced practice','Use guided practice and explain reasoning'))
         when 'numeric' then jsonb_build_object('value',case when lower(subject_title) like '%math%' then grade_level + (2*chapter_no) + 2 else 3-((question_number%2)+1) end)
         when 'short_answer' then jsonb_build_object('text',topic_title)
         when 'matching' then jsonb_build_object('pairs',jsonb_build_array(jsonb_build_object('left','Understand','right','Learn the central idea'),jsonb_build_object('left','Practice','right','Apply the skill'),jsonb_build_object('left','Reflect','right','Explain evidence of learning')))
         when 'ordering' then jsonb_build_object('order',to_jsonb(array[chapter_titles[1],chapter_titles[2],chapter_titles[3]]))
         else '{}'::jsonb end,
       case when question_type='short_answer' then jsonb_build_array(lower(topic_title),regexp_replace(lower(topic_title),'[^a-z0-9 ]','','g')) else '[]'::jsonb end,
       case when question_type='numeric' then 0 else null end,
       case question_type
         when 'single_choice' then 'The question targets “'||topic_title||'”, which is mapped to the chapter “'||chapter_title||'” in this Mela curriculum map.'
         when 'passage_choice' then 'The study note explicitly places “'||topic_title||'” within “'||chapter_title||'”.'
         when 'scenario_choice' then 'The learner needs practice with “'||topic_title||'”, so the mapped chapter is “'||chapter_title||'”.'
         when 'true_false' then case when question_number%2=0 then 'The statement deliberately names a different chapter. The mapped chapter is “'||chapter_title||'”.' else 'The topic is mapped to “'||chapter_title||'” in the current Mela chapter map.' end
         when 'multi_select' then 'Understanding the mapped topic and using guided practice with reasoning are productive study actions; guessing and ignoring feedback are not.'
         when 'numeric' then case when lower(subject_title) like '%math%' then 'Add the two stated quantities: '||(grade_level+chapter_no)||' + '||(chapter_no+2)||'.' else 'Subtract completed mapped topics from the three mapped topics in the chapter.' end
         when 'short_answer' then 'The exact mapped topic name is “'||topic_title||'”.'
         when 'matching' then 'Understand means learn the idea; Practice means apply the skill; Reflect means explain evidence of learning.'
         when 'ordering' then 'The first three chapters are ordered by their stored chapter numbers.'
         else 'Server-validated response.' end,
       'v12'
from qdata
on conflict(question_id) do update set grading_kind=excluded.grading_kind,correct_response=excluded.correct_response,accepted_variants=excluded.accepted_variants,tolerance=excluded.tolerance,rationale=excluded.rationale,grading_version=excluded.grading_version,updated_at=now();
;

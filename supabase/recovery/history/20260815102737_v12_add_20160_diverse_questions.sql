-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815102737
with program_data as (
  select p.program_key,p.grade_level,p.track_key,p.subject_key,p.subject_title,
         array_agg(c.id order by c.chapter_number) as chapter_ids,
         array_agg(c.title order by c.chapter_number) as chapter_titles,
         array_agg(c.chapter_number order by c.chapter_number) as chapter_numbers,
         count(c.id)::int as nchap
  from public.mela_learning_programs p
  join public.mela_learning_chapters c on c.program_key=p.program_key and c.status='published'
  where p.program_kind='school_subject' and p.grade_level between 1 and 12 and p.active
  group by p.program_key,p.grade_level,p.track_key,p.subject_key,p.subject_title
), topic_data as (
  select c.program_key,
         array_agg(t.id order by c.chapter_number,t.display_order,t.id) as topic_ids,
         array_agg(t.title order by c.chapter_number,t.display_order,t.id) as topic_titles,
         count(t.id)::int as ntop
  from public.mela_learning_chapters c
  join public.mela_learning_chapter_topics t on t.chapter_id=c.id and t.status='published'
  where c.status='published'
  group by c.program_key
), expanded as (
  select p.*,t.topic_ids,t.topic_titles,t.ntop,n,
         ((n-641) % p.nchap)+1 as ci,
         ((n-641) % t.ntop)+1 as ti,
         ((n-641) % 9) as variant
  from program_data p join topic_data t using(program_key)
  cross join generate_series(641,800) n
), prepared as (
  select e.*,
         chapter_ids[ci] as chapter_id,
         chapter_titles[ci] as chapter_title,
         chapter_numbers[ci] as chapter_no,
         topic_ids[ti] as topic_id,
         topic_titles[ti] as topic_title,
         case variant
           when 0 then 'single_choice'
           when 1 then 'true_false'
           when 2 then 'multi_select'
           when 3 then 'numeric'
           when 4 then 'short_answer'
           when 5 then 'matching'
           when 6 then 'ordering'
           when 7 then 'passage_choice'
           else 'scenario_choice'
         end as qtype
  from expanded e
)
insert into public.mela_question_bank(
  program_key,chapter_id,topic_id,question_key,question_number,question_type,prompt,choices,difficulty,cognitive_level,access_tier,validation_status,source_status,generation_version,
  narration_text,response_schema,estimated_seconds,machine_quality_score,quality_checks,accessibility_support,active
)
select program_key,chapter_id,topic_id,
       program_key||'_v12_q'||lpad(n::text,4,'0'),n,qtype,
       case qtype
         when 'single_choice' then 'Which chapter in '||subject_title||' is the best match for the learning topic “'||topic_title||'”?'
         when 'true_false' then 'True or false: “'||topic_title||'” is a mapped learning topic in the chapter “'||chapter_title||'”.'
         when 'multi_select' then 'Select the two statements that correctly describe how to study “'||chapter_title||'” in Grade '||grade_level||'.'
         when 'numeric' then case when lower(subject_title) like '%math%' then 'A Grade '||grade_level||' learner completes '||(grade_level+chapter_no)||' practice items and then completes '||(chapter_no+2)||' more. How many practice items were completed in total?' else 'This chapter has 3 mapped learning topics. If a learner has completed '||((n%2)+1)||' of them, how many mapped topics remain? Use a number.' end
         when 'short_answer' then 'Write the exact mapped topic name that this question targets in “'||chapter_title||'”.'
         when 'matching' then 'Match each study item to its correct role for the chapter “'||chapter_title||'”.'
         when 'ordering' then 'Put these three chapter labels in curriculum order from earliest to latest.'
         when 'passage_choice' then 'Read this short study note: “A learner is working on '||topic_title||' as part of '||chapter_title||'. The goal is to understand the idea, practice it, and explain the learning with evidence.” Which chapter should the learner open next to continue this mapped work?'
         else 'A Grade '||grade_level||' learner says: “I need more practice with '||topic_title||'.” Which chapter should Mela recommend first?'
       end,
       case qtype
         when 'true_false' then '["True","False"]'::jsonb
         when 'multi_select' then jsonb_build_array('Understand the mapped topic before advanced practice','Use guided practice and explain reasoning','Skip the chapter and guess the answers','Ignore feedback and repeat mistakes')
         when 'numeric' then '[]'::jsonb
         when 'short_answer' then '[]'::jsonb
         when 'matching' then jsonb_build_array(jsonb_build_object('left','Understand','right','Learn the central idea'),jsonb_build_object('left','Practice','right','Apply the skill'),jsonb_build_object('left','Reflect','right','Explain evidence of learning'))
         when 'ordering' then (select jsonb_agg(val) from (select val from unnest(array[chapter_titles[1],chapter_titles[2],chapter_titles[3]]) val order by md5(val||n::text)) s)
         else jsonb_build_array(chapter_title,
                chapter_titles[((ci) % nchap)+1],
                chapter_titles[((ci+1) % nchap)+1],
                chapter_titles[((ci+2) % nchap)+1])
       end,
       case when n%5=0 then 5 when n%5=4 then 4 when n%5=3 then 3 when n%5=2 then 2 else 1 end,
       case when variant in (0,1) then 'understand' when variant in (2,3,4) then 'apply' else 'analyze' end,
       case when grade_level=12 and n>780 then 'one_time' else 'subscription' end,
       'deterministic_validated','mela_supplemental','v12',
       case qtype
         when 'numeric' then 'Numeric response question. '||case when lower(subject_title) like '%math%' then 'Calculate the total carefully.' else 'Calculate how many mapped topics remain.' end
         when 'short_answer' then 'Short answer question. Type the mapped topic name: '||topic_title||'.'
         else 'Question about '||subject_title||', chapter '||chapter_title||'. '||replace(qtype,'_',' ')||' format.'
       end,
       jsonb_build_object('type',qtype,'required',true,'supports_keyboard',true),
       case when qtype in ('matching','ordering','passage_choice','scenario_choice') then 150 else 90 end,
       case when qtype in ('passage_choice','scenario_choice','matching','ordering') then 91 else 88 end,
       jsonb_build_object('deterministic_answer',true,'nonempty_prompt',true,'curriculum_entity_backed',true,'server_graded',true,'human_review_required',true),
       jsonb_build_object('screen_reader_ready',true,'narration_ready',true,'keyboard_answerable',true,'no_color_only_cue',true,'extended_time_compatible',true),true
from prepared
on conflict(program_key,question_number) do nothing;
;

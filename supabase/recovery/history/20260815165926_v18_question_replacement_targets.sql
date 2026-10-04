-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815165926
truncate private.mela_question_replacement_targets_v18 cascade;
with topic_stats as (
  select q.topic_id,count(*) filter(where q.validation_status in ('deterministic_validated','educator_verified'))::int mastery_count
  from public.mela_question_bank q where q.active and q.topic_id is not null group by q.topic_id
), base as (
  select q.id target_question_id,q.program_key,q.chapter_id,q.topic_id,p.grade_level,p.subject_title,q.question_type,q.access_tier,q.question_number,
         coalesce(ts.mastery_count,0) topic_mastery,
         row_number() over(partition by q.program_key,q.topic_id order by q.question_number) within_topic_rank
  from public.mela_question_bank q
  join public.mela_learning_programs p on p.program_key=q.program_key
  left join topic_stats ts on ts.topic_id=q.topic_id
  where q.active and q.validation_status='review_required' and p.program_kind='school_subject' and p.grade_level between 1 and 12
), ranked as (
  select b.*,row_number() over(partition by b.program_key order by b.within_topic_rank,b.topic_mastery,b.chapter_id,b.topic_id,b.question_number) program_rank
  from base b
)
insert into private.mela_question_replacement_targets_v18(target_question_id,program_key,chapter_id,topic_id,grade_level,subject_title,current_question_type,desired_question_type,access_tier,priority,target_reason)
select r.target_question_id,r.program_key,r.chapter_id,r.topic_id,r.grade_level,r.subject_title,r.question_type,r.question_type,r.access_tier,
       10+r.topic_mastery+r.within_topic_rank,
       case when r.topic_mastery=0 then 'topic has zero mastery candidates' when r.topic_mastery<5 then 'topic below minimum mastery practice coverage' else 'program below 500 mastery target' end
from ranked r join private.mela_question_regeneration_queue_v18 q on q.program_key=r.program_key
where r.program_rank<=q.questions_needed;
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815164811
truncate private.mela_question_review_slices_v18 restart identity;
with ranked as (
 select q.program_key,q.id,q.question_number,
        ((row_number() over(partition by q.program_key order by q.question_number)-1)/100)::int+1 slice_number
 from public.mela_question_bank q
 join private.mela_question_quality_audit_v18 a on a.question_id=q.id
 where q.active and a.purpose_class='subject_mastery_candidate'
), grouped as (
 select program_key,slice_number,array_agg(id order by question_number) ids,count(*) n
 from ranked group by program_key,slice_number
)
insert into private.mela_question_review_slices_v18(program_key,slice_number,question_ids,question_count)
select program_key,slice_number,ids,n from grouped;
;

-- Operator-controlled review coverage reconciliation; staging first.
-- Run through an authorized, audited maintenance session AFTER inspecting the
-- dry-run counts and confirming the actual production MELA project.
-- Never publish teacher-approval decisions automatically.
--
-- DRY RUN (before writing):
with existing as (
  select distinct unnest(question_ids) as question_id
  from private.mela_question_review_slices_v18
)
select
  (select count(*) from public.mela_question_bank where active) as active_question_count,
  (select count(*) from public.mela_question_bank q join existing e on e.question_id=q.id where q.active) as active_in_review_queue,
  (select count(*) from public.mela_question_bank q left join existing e on e.question_id=q.id where q.active and e.question_id is null) as missing_from_review_queue;

-- IMPORTANT: The following insert is intentionally commented out.
-- Uncomment ONLY after approval of the above dry-run and after a staging test
-- verifies that no duplicate UUIDs are introduced. An entire real corpus may
-- require chunked reconciliation to respect transaction and runtime limits.

/*
with existing as materialized (
  select distinct unnest(question_ids) as question_id
  from private.mela_question_review_slices_v18
),
missing as (
  select q.id, q.program_key, q.question_number
  from public.mela_question_bank q
  left join existing e on e.question_id=q.id
  where q.active and e.question_id is null
),
ranked as (
  select m.id,m.program_key,
    ((row_number() over (partition by m.program_key order by m.question_number,m.id)-1)/100)::integer + 1 as new_slice
  from missing m
),
max_slices as (
  select program_key,coalesce(max(slice_number),0) as max_number
  from private.mela_question_review_slices_v18 group by program_key
),
new_slices as (
  select r.program_key,coalesce(x.max_number,0)+r.new_slice as slice_number,
    array_agg(r.id order by r.id) as question_ids,count(*)::integer as question_count
  from ranked r left join max_slices x on x.program_key=r.program_key
  group by r.program_key,x.max_number,r.new_slice
)
insert into private.mela_question_review_slices_v18
  (program_key,slice_number,question_ids,question_count,review_scope,status)
select program_key,slice_number,question_ids,question_count,
  'full_bank_reconciliation','pending'
from new_slices
order by program_key,slice_number
on conflict(program_key,slice_number) do nothing;
*/

-- Post-verification: re-run the dry run. It must report 0 missing.
-- Check status remains pending for newly inserted slices; human review must
-- progress from pending to approved/changes_required with real reviewer IDs.

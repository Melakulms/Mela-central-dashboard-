-- Pure, no-write sample cases for the same exact subject/grade predicate used
-- by private.question_reviewer_allowed_v18. Any failed case raises an error.
do $test$
declare failed text;
begin
  with cases(label, taught_subjects, taught_levels, program_subject, program_grade, program_stage, expected) as (
    values
      ('correct school subject and grade', array['mathematics'], array['7'], 'Mathematics', 7, 'school_7_8', true),
      ('reject wrong school grade', array['Mathematics'], array['7'], 'Mathematics', 12, 'school_11_12', false),
      ('reject wrong subject', array['Biology'], array['7'], 'Mathematics', 7, 'school_7_8', false),
      ('allow matching tertiary stage', array['digital literacy'], array['university'], 'Digital Literacy', null::integer, 'university', true),
      ('reject wrong tertiary stage', array['Digital Literacy'], array['college_tvet'], 'Digital Literacy', null::integer, 'university', false)
  ), outcomes as (
    select label,
      (
        exists(select 1 from unnest(taught_subjects) s where lower(btrim(s))=lower(btrim(program_subject)))
        and exists(select 1 from unnest(taught_levels) g where lower(btrim(g))=coalesce(program_grade::text,lower(btrim(program_stage))))
      ) as allowed, expected
    from cases
  )
  select string_agg(label,', ') into failed from outcomes where allowed is distinct from expected;
  if failed is not null then raise exception 'Teacher grade/subject permission predicate failed: %',failed; end if;
end $test$;

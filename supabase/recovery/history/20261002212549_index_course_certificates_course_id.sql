-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002212549
create index if not exists course_certificates_course_id_idx on public.course_certificates(course_id);
;

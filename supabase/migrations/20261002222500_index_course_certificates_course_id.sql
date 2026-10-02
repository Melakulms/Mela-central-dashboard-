-- Production-applied final schema performance fix.
-- Index the only public foreign-key column found without a supporting index.
create index if not exists course_certificates_course_id_idx
  on public.course_certificates(course_id);

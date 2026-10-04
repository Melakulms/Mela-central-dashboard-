-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812232306
create index if not exists practice_attempts_reviewed_by_idx on public.practice_attempts(reviewed_by) where reviewed_by is not null;
create index if not exists practice_mastery_topic_idx on public.practice_mastery(topic_id);
create index if not exists practice_topics_module_idx on public.practice_topics(module_id) where module_id is not null;
;

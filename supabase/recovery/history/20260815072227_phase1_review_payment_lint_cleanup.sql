-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815072227
create index if not exists mela_chapter_review_queue_program_idx on public.mela_chapter_review_queue(program_key);
create index if not exists mela_learning_payment_attempts_entitlement_idx on public.mela_learning_payment_attempts(entitlement_id) where entitlement_id is not null;

drop policy if exists mela_chapter_review_queue_admin_read on public.mela_chapter_review_queue;
drop policy if exists mela_chapter_review_queue_admin_write on public.mela_chapter_review_queue;
drop policy if exists mela_chapter_review_queue_admin_all on public.mela_chapter_review_queue;
create policy mela_chapter_review_queue_admin_all on public.mela_chapter_review_queue
for all to authenticated using(private.is_admin_user()) with check(private.is_admin_user());
;

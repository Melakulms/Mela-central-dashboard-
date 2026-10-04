-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260809173247
drop index if exists public.payments_one_success_per_user_course_idx;
create index if not exists payments_success_user_course_idx on public.payments(user_id, course_id) where status = 'success';
;

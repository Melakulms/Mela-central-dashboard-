-- No-write regression for verified educator scope.
do $test$
begin
 if has_function_privilege('anon','public.review_teacher_profile_scoped(uuid,text,text,text[])','EXECUTE') then
   raise exception 'Anonymous users must not be able to approve teacher subjects';
 end if;
 if not exists (
   select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='private' and p.proname='review_teacher_profile_scoped' and
    position('not exists(select 1 from unnest(v_before.subjects_taught)' in pg_get_functiondef(p.oid))>0
 ) then raise exception 'Teacher subject subset validation not found'; end if;
 if not exists (
   select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='private' and p.proname='review_teacher_profile' and
    position('Use subject-scoped credential-based teacher approval' in pg_get_functiondef(p.oid))>0
 ) then raise exception 'Old unrestricted teacher approval must be disabled'; end if;
 if not exists (
   select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='private' and p.proname='question_reviewer_allowed_v18' and
    position('educator_review_authorizations' in pg_get_functiondef(p.oid))>0
 ) then raise exception 'Question review no longer intersects authorized teacher subjects'; end if;
end $test$;

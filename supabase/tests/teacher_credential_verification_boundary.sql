-- Non-mutating verification of the live credential security boundary.
do $test$
declare blocked text;
begin
 if not exists(select 1 from storage.buckets where id='teacher-credentials' and not public) then
   raise exception 'teacher document bucket missing or public';
 end if;
 if not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='teacher_credential_documents' and c.relrowsecurity) then
   raise exception 'credential evidence RLS disabled';
 end if;
 if has_table_privilege('anon','public.teacher_credential_documents','SELECT') or
    has_table_privilege('authenticated','public.teacher_credential_documents','UPDATE') or
    has_table_privilege('authenticated','public.teacher_credential_documents','DELETE') or
    has_column_privilege('authenticated','public.teacher_credential_documents','review_status','INSERT') then
   raise exception 'credential verification fields exposed to an untrusted client';
 end if;
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects'
   and policyname='tc_restrict_select' and permissive='RESTRICTIVE') then
   raise exception 'storage missing restrictive cross-account read gate';
 end if;
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects'
   and policyname='tc_restrict_update' and permissive='RESTRICTIVE') or
    not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects'
   and policyname='tc_restrict_delete' and permissive='RESTRICTIVE') then
   raise exception 'document replacement/deletion incorrectly permitted';
 end if;
 if has_function_privilege('anon','public.review_teacher_credential_document(uuid,text,text)','EXECUTE') then
   raise exception 'anonymous users can approve teacher documents';
 end if;
 if position('teacher_credential_documents' in (
  select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='review_teacher_profile'))=0 then
   raise exception 'teacher approval is not blocked without verified evidence';
 end if;
 if position('teacher_credential_documents' in (
  select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='question_reviewer_allowed_v18'))=0 then
   raise exception 'question review eligibility is not tied to verified evidence';
 end if;
end $test$;

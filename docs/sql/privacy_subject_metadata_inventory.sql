-- MELA privacy subject-data inventory: metadata ONLY. Safe for read-only
-- inspection in production or staging. No user rows or file contents.
-- Record output as a dated snapshot, not a verified erasure/export list.

-- 1. Application base table totals and direct user/profile foreign-key coverage.
WITH app_tables AS (
 SELECT c.oid,n.nspname AS schema_name,c.relname AS table_name
 FROM pg_catalog.pg_class c
 JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind='r' AND n.nspname IN ('public','private','admin')
), ref AS (
 SELECT DISTINCT conrelid,confrelid FROM pg_catalog.pg_constraint
 WHERE contype='f'
)
SELECT COUNT(*) AS application_tables,
 COUNT(*) FILTER (WHERE schema_name='public') AS public_tables,
 COUNT(*) FILTER (WHERE schema_name='private') AS private_tables,
 COUNT(*) FILTER (WHERE schema_name='admin') AS admin_tables,
 (SELECT COUNT(DISTINCT conrelid) FROM ref WHERE confrelid='public.profiles'::regclass)
  AS direct_profiles_fk_tables,
 (SELECT COUNT(DISTINCT conrelid) FROM ref WHERE confrelid='auth.users'::regclass)
  AS direct_auth_users_fk_tables,
 (SELECT COUNT(DISTINCT conrelid) FROM ref WHERE confrelid IN (
   'public.profiles'::regclass,'auth.users'::regclass))
  AS distinct_direct_identity_fk_tables
FROM app_tables;

-- 2. Candidate personal identifiers without an immediate profile/Auth FK.
-- This is a coarse heuristic: the true scope also includes indirect links,
-- text, JSON, documents, event payloads and external processor data.
WITH person_columns AS (
 SELECT table_schema,table_name,
 STRING_AGG(column_name,', ' ORDER BY ordinal_position)
 FILTER(WHERE column_name ~* '(user_id|owner_id|learner_id|guardian_id|mentor_id|teacher_id|parent_id|student_id|applicant_id|actor_user_id|recipient_id|sender_id|subject_id|person_id)')
 AS likely_person_columns
 FROM information_schema.columns
 WHERE table_schema IN ('public','private','admin')
 GROUP BY table_schema,table_name
), direct_refs AS (
 SELECT DISTINCT n.nspname AS schema_name,c.relname AS table_name
 FROM pg_catalog.pg_constraint fk
 JOIN pg_catalog.pg_class c ON c.oid=fk.conrelid
 JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 WHERE fk.contype='f'
 AND fk.confrelid IN ('public.profiles'::regclass,'auth.users'::regclass)
)
SELECT person_columns.table_schema,person_columns.table_name,
 person_columns.likely_person_columns
FROM person_columns
LEFT JOIN direct_refs ON person_columns.table_schema=direct_refs.schema_name
 AND person_columns.table_name=direct_refs.table_name
WHERE person_columns.likely_person_columns IS NOT NULL
  AND direct_refs.table_name IS NULL
ORDER BY person_columns.table_schema,person_columns.table_name;

-- 3. Auth/profile deletion dependencies — review cascades and SET NULL.
-- PostgreSQL confdeltype: a=NO ACTION, r=RESTRICT, c=CASCADE,
-- n=SET NULL, d=SET DEFAULT. Do not infer legal erasure policy from FK action.
SELECT fk.conrelid::regclass::text AS dependent_table,
 fk.confrelid::regclass::text AS identity_parent,
 CASE fk.confdeltype WHEN 'a' THEN 'NO ACTION'
  WHEN 'r' THEN 'RESTRICT'
  WHEN 'c' THEN 'CASCADE'
  WHEN 'n' THEN 'SET NULL'
  WHEN 'd' THEN 'SET DEFAULT' ELSE 'UNKNOWN' END AS fk_delete_behavior,
 COUNT(*) AS constraint_count
FROM pg_catalog.pg_constraint fk
WHERE fk.contype='f'
 AND fk.confrelid IN ('public.profiles'::regclass,'auth.users'::regclass)
GROUP BY fk.conrelid,fk.confrelid,fk.confdeltype
ORDER BY dependent_table,identity_parent,fk_delete_behavior;

-- 4. Storage buckets: metadata only. Does not establish object-owner identity,
-- object-level RLS, remote copies or retention status.
SELECT name,public,file_size_limit,allowed_mime_types
FROM storage.buckets ORDER BY name;

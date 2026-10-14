-- Keep legacy administration tied to the same central registry and MFA boundary.
CREATE OR REPLACE FUNCTION public.mela_is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$ SELECT auth.uid() IS NOT NULL AND private.is_admin_user(); $$;
REVOKE ALL ON FUNCTION public.mela_is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mela_is_admin() TO anon, authenticated, service_role;

-- Preserve each ownership/participant predicate and change only the obsolete
-- profile-role admin arm. Using the public wrapper keeps anonymous catalogue
-- policies from needing access to the private schema.
DO $migration$
DECLARE p record; statement text;
BEGIN
  FOR p IN SELECT * FROM pg_policies WHERE schemaname='public'
    AND (position('(p.role = ''admin''::user_role)' in coalesce(qual,''))>0
      OR position('(p.role = ''admin''::user_role)' in coalesce(with_check,''))>0)
  LOOP
    statement := format('ALTER POLICY %I ON public.%I',p.policyname,p.tablename);
    IF p.qual IS NOT NULL THEN
      statement := statement || ' USING (' || replace(p.qual,'(p.role = ''admin''::user_role)','public.mela_is_admin()') || ')';
    END IF;
    IF p.with_check IS NOT NULL THEN
      statement := statement || ' WITH CHECK (' || replace(p.with_check,'(p.role = ''admin''::user_role)','public.mela_is_admin()') || ')';
    END IF;
    EXECUTE statement;
  END LOOP;
END $migration$;

CREATE OR REPLACE FUNCTION private.current_account_can_access()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
 SELECT coalesce((SELECT p.account_status='active' AND p.deleted_at IS NULL
   AND (p.email_verified OR p.phone_verified)
   FROM public.profiles p WHERE p.id=auth.uid()),false);
$$;

-- Scores displayed as assessment results must be written by trusted grading code.
REVOKE INSERT, UPDATE, DELETE ON public.skill_assessment_results FROM anon, authenticated;
DROP POLICY IF EXISTS assessment_self_insert ON public.skill_assessment_results;

-- Internal maintenance functions are called by trusted triggers/backend jobs.
-- They accept arbitrary user IDs and are not user-facing RPCs.
REVOKE EXECUTE ON FUNCTION private.refresh_course_enrollment_from_lessons(uuid,uuid),
  private.refresh_course_enrollment_after_lesson_progress(),
  private.refresh_mentor_rating_summary(uuid), private.refresh_mentor_rating_summary_trigger(),
  private.close_expired_opportunities(), private.enforce_feature_kill_switch_write(),
  private.guard_application_update() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.refresh_course_enrollment_from_lessons(uuid,uuid),
  private.refresh_course_enrollment_after_lesson_progress(),
  private.refresh_mentor_rating_summary(uuid), private.refresh_mentor_rating_summary_trigger(),
  private.close_expired_opportunities(), private.enforce_feature_kill_switch_write(),
  private.guard_application_update() TO service_role;

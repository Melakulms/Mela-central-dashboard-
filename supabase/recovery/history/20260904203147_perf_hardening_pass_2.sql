-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260904203147

-- 1. Drop duplicate/redundant indexes (keep the one backing the actual UNIQUE constraint)
DROP INDEX IF EXISTS public.uq_assessment_attempt_question_once;

DROP INDEX IF EXISTS public.course_enrollments_unique_user_course;
DROP INDEX IF EXISTS public.course_enrollments_user_course_uidx;
DROP INDEX IF EXISTS public.course_enrollments_user_course_unique;
DROP INDEX IF EXISTS public.ux_course_enrollment_user_course;
DROP INDEX IF EXISTS public.ux_course_enrollments_user_course;

DROP INDEX IF EXISTS public.course_lessons_unique_position;

DROP INDEX IF EXISTS public.lesson_progress_user_lesson_unique;
DROP INDEX IF EXISTS public.ux_lesson_progress_user_lesson;

DROP INDEX IF EXISTS public.student_lesson_progress_user_lesson_uidx;
DROP INDEX IF EXISTS public.student_lesson_progress_user_lesson_unique;
DROP INDEX IF EXISTS public.ux_student_lesson_progress_user_lesson;

DROP INDEX IF EXISTS public.student_module_progress_user_module_unique;

-- 2. Add missing covering index for FK
CREATE INDEX IF NOT EXISTS idx_installment_schedule_payment_id
  ON public.installment_schedule (payment_id);

-- 3. Split overlapping ALL admin policies into write-only (INSERT/UPDATE/DELETE)
-- so they no longer duplicate-evaluate against the existing SELECT policies.

-- mela_ai_agent_tools
DROP POLICY IF EXISTS mela_ai_agent_tools_admin ON public.mela_ai_agent_tools;
CREATE POLICY mela_ai_agent_tools_admin_insert ON public.mela_ai_agent_tools
  FOR INSERT TO authenticated WITH CHECK (private.is_admin_user());
CREATE POLICY mela_ai_agent_tools_admin_update ON public.mela_ai_agent_tools
  FOR UPDATE TO authenticated USING (private.is_admin_user()) WITH CHECK (private.is_admin_user());
CREATE POLICY mela_ai_agent_tools_admin_delete ON public.mela_ai_agent_tools
  FOR DELETE TO authenticated USING (private.is_admin_user());

-- mela_ai_agents
DROP POLICY IF EXISTS mela_ai_agents_admin ON public.mela_ai_agents;
CREATE POLICY mela_ai_agents_admin_insert ON public.mela_ai_agents
  FOR INSERT TO authenticated WITH CHECK (private.is_admin_user());
CREATE POLICY mela_ai_agents_admin_update ON public.mela_ai_agents
  FOR UPDATE TO authenticated USING (private.is_admin_user()) WITH CHECK (private.is_admin_user());
CREATE POLICY mela_ai_agents_admin_delete ON public.mela_ai_agents
  FOR DELETE TO authenticated USING (private.is_admin_user());

-- mela_ai_model_routes
DROP POLICY IF EXISTS mela_ai_model_routes_admin_write ON public.mela_ai_model_routes;
CREATE POLICY mela_ai_model_routes_admin_insert ON public.mela_ai_model_routes
  FOR INSERT TO authenticated WITH CHECK (private.is_admin_user());
CREATE POLICY mela_ai_model_routes_admin_update ON public.mela_ai_model_routes
  FOR UPDATE TO authenticated USING (private.is_admin_user()) WITH CHECK (private.is_admin_user());
CREATE POLICY mela_ai_model_routes_admin_delete ON public.mela_ai_model_routes
  FOR DELETE TO authenticated USING (private.is_admin_user());

-- mela_ai_tools
DROP POLICY IF EXISTS mela_ai_tools_admin ON public.mela_ai_tools;
CREATE POLICY mela_ai_tools_admin_insert ON public.mela_ai_tools
  FOR INSERT TO authenticated WITH CHECK (private.is_admin_user());
CREATE POLICY mela_ai_tools_admin_update ON public.mela_ai_tools
  FOR UPDATE TO authenticated USING (private.is_admin_user()) WITH CHECK (private.is_admin_user());
CREATE POLICY mela_ai_tools_admin_delete ON public.mela_ai_tools
  FOR DELETE TO authenticated USING (private.is_admin_user());

;

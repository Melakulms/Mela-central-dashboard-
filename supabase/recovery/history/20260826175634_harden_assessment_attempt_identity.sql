-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826175634
CREATE OR REPLACE FUNCTION public.guard_assessment_attempt_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP='UPDATE' AND NOT public.is_admin_user(auth.uid()) THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.assessment_id IS DISTINCT FROM OLD.assessment_id
       OR NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.attempt_no IS DISTINCT FROM OLD.attempt_no
       OR NEW.started_at IS DISTINCT FROM OLD.started_at
       OR NEW.proctored IS DISTINCT FROM OLD.proctored
       OR NEW.language_code IS DISTINCT FROM OLD.language_code THEN
      RAISE EXCEPTION 'Assessment attempt identity/configuration is immutable';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_assessment_attempt_mutation ON public.assessment_attempts;
CREATE TRIGGER trg_guard_assessment_attempt_mutation
BEFORE UPDATE ON public.assessment_attempts
FOR EACH ROW EXECUTE FUNCTION public.guard_assessment_attempt_mutation();

CREATE UNIQUE INDEX IF NOT EXISTS uq_assessment_attempt_question_once
ON public.assessment_responses(attempt_id, question_id);
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826170247
CREATE OR REPLACE FUNCTION private.protect_interview_identity() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$ BEGIN IF NOT private.is_admin_user() AND NEW.application_id IS DISTINCT FROM OLD.application_id THEN RAISE EXCEPTION 'Interview application cannot be changed'; END IF; RETURN NEW; END; $fn$; DROP TRIGGER IF EXISTS trg_protect_interview_identity ON public.interviews; CREATE TRIGGER trg_protect_interview_identity BEFORE UPDATE ON public.interviews FOR EACH ROW EXECUTE FUNCTION private.protect_interview_identity();
;

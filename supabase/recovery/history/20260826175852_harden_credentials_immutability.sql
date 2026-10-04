-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826175852
ALTER TABLE public.skill_academy_certificates DROP CONSTRAINT IF EXISTS skill_academy_certificates_progress_valid;
ALTER TABLE public.skill_academy_certificates ADD CONSTRAINT skill_academy_certificates_progress_valid CHECK (final_progress BETWEEN 0 AND 100);
CREATE UNIQUE INDEX IF NOT EXISTS uq_skill_academy_certificates_code_ci ON public.skill_academy_certificates (lower(certificate_code));
ALTER TABLE public.verified_skills DROP CONSTRAINT IF EXISTS verified_skills_level_valid;
ALTER TABLE public.verified_skills ADD CONSTRAINT verified_skills_level_valid CHECK (lower(level) IN ('beginner','intermediate','advanced','expert'));

CREATE OR REPLACE FUNCTION public.guard_credential_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT private.is_admin_user() THEN
    IF TG_TABLE_NAME='skill_academy_certificates' THEN
      IF NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.career_path_id IS DISTINCT FROM OLD.career_path_id OR NEW.certificate_code IS DISTINCT FROM OLD.certificate_code OR NEW.final_progress IS DISTINCT FROM OLD.final_progress OR NEW.metadata IS DISTINCT FROM OLD.metadata OR NEW.issued_at IS DISTINCT FROM OLD.issued_at THEN
        RAISE EXCEPTION 'Certificate identity and issuance fields are immutable';
      END IF;
      IF OLD.revoked_at IS NOT NULL AND (NEW.revoked_at IS DISTINCT FROM OLD.revoked_at OR NEW.revoke_reason IS DISTINCT FROM OLD.revoke_reason) THEN
        RAISE EXCEPTION 'Revoked certificate state is immutable';
      END IF;
    ELSIF TG_TABLE_NAME='verified_skills' THEN
      IF NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.skill_name IS DISTINCT FROM OLD.skill_name OR NEW.category IS DISTINCT FROM OLD.category OR NEW.level IS DISTINCT FROM OLD.level OR NEW.score IS DISTINCT FROM OLD.score OR NEW.verification_source IS DISTINCT FROM OLD.verification_source OR NEW.issued_at IS DISTINCT FROM OLD.issued_at THEN
        RAISE EXCEPTION 'Verified skill identity and evidence fields are immutable';
      END IF;
      IF OLD.verified IS TRUE AND NEW.verified IS DISTINCT FROM OLD.verified THEN
        RAISE EXCEPTION 'Verified status cannot be downgraded by non-admin users';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_guard_certificate_mutation ON public.skill_academy_certificates;
CREATE TRIGGER trg_guard_certificate_mutation BEFORE UPDATE ON public.skill_academy_certificates FOR EACH ROW EXECUTE FUNCTION public.guard_credential_mutation();
DROP TRIGGER IF EXISTS trg_guard_verified_skill_mutation ON public.verified_skills;
CREATE TRIGGER trg_guard_verified_skill_mutation BEFORE UPDATE ON public.verified_skills FOR EACH ROW EXECUTE FUNCTION public.guard_credential_mutation();
;

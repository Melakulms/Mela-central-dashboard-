-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260827140050
CREATE OR REPLACE FUNCTION public.guard_guardian_relationship_identity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF TG_OP='UPDATE' AND NOT public.is_admin_user(auth.uid()) THEN
    IF NEW.learner_id IS DISTINCT FROM OLD.learner_id
       OR NEW.guardian_user_id IS DISTINCT FROM OLD.guardian_user_id
       OR NEW.guardian_email IS DISTINCT FROM OLD.guardian_email
       OR NEW.guardian_phone IS DISTINCT FROM OLD.guardian_phone
       OR NEW.consent_version IS DISTINCT FROM OLD.consent_version
       OR NEW.verified_at IS DISTINCT FROM OLD.verified_at
       OR NEW.verified_by IS DISTINCT FROM OLD.verified_by
       OR NEW.requested_at IS DISTINCT FROM OLD.requested_at THEN
      RAISE EXCEPTION 'Guardian relationship identity and verification fields are immutable for non-admin users';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_guardian_relationship_identity ON public.guardian_relationships;
CREATE TRIGGER trg_guard_guardian_relationship_identity
BEFORE UPDATE ON public.guardian_relationships
FOR EACH ROW EXECUTE FUNCTION public.guard_guardian_relationship_identity();
REVOKE EXECUTE ON FUNCTION public.guard_guardian_relationship_identity() FROM PUBLIC, anon, authenticated;

CREATE UNIQUE INDEX IF NOT EXISTS guardian_relationship_verified_pair_unique
ON public.guardian_relationships (learner_id, guardian_user_id)
WHERE guardian_user_id IS NOT NULL AND verified_at IS NOT NULL;
;

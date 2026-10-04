-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826161238
CREATE OR REPLACE FUNCTION private.protect_application_identity_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NOT private.is_admin_user() THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.applicant_id IS DISTINCT FROM OLD.applicant_id
       OR NEW.opportunity_id IS DISTINCT FROM OLD.opportunity_id THEN
      RAISE EXCEPTION 'Application identity fields cannot be changed after creation';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_protect_application_identity_fields ON public.applications;
CREATE TRIGGER trg_protect_application_identity_fields
BEFORE UPDATE ON public.applications
FOR EACH ROW
EXECUTE FUNCTION private.protect_application_identity_fields();
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821220237
CREATE OR REPLACE FUNCTION private.application_update_actor(p_application_id uuid)
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT CASE
    WHEN private.is_admin_user() THEN 'admin'
    WHEN EXISTS (
      SELECT 1 FROM public.applications a
      JOIN public.opportunities o ON o.id = a.opportunity_id
      WHERE a.id = p_application_id AND private.has_employer_access(o.employer_id, true)
    ) THEN 'employer'
    WHEN EXISTS (
      SELECT 1 FROM public.applications a
      WHERE a.id = p_application_id AND a.applicant_id = auth.uid()
    ) THEN 'applicant'
    ELSE NULL
  END;
$function$;

REVOKE ALL ON FUNCTION private.application_update_actor(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.application_update_actor(uuid) TO authenticated;

DROP POLICY IF EXISTS "Applications update by authorized actors" ON public.applications;
CREATE POLICY "Applications update by authorized actors"
ON public.applications
FOR UPDATE TO authenticated
USING (
  private.application_update_actor(id) IS NOT NULL
  AND (
    private.application_update_actor(id) IN ('employer','admin')
    OR (private.application_update_actor(id) = 'applicant' AND status NOT IN ('hired','rejected','withdrawn'))
  )
)
WITH CHECK (
  (private.application_update_actor(id) = 'applicant' AND status = 'withdrawn')
  OR (
    private.application_update_actor(id) IN ('employer','admin')
    AND status IN ('submitted','reviewing','shortlisted','interview','offered','hired','rejected')
  )
);
;

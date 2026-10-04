-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821220044
DROP POLICY IF EXISTS "Users edit employer registration request" ON public.employer_registration_requests;
CREATE POLICY "Users edit employer registration request" ON public.employer_registration_requests
FOR UPDATE TO authenticated
USING (
  applicant_user_id = (SELECT auth.uid())
  OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = (SELECT auth.uid()) AND p.role = 'admin'::public.user_role)
)
WITH CHECK (
  (
    applicant_user_id = (SELECT auth.uid())
    AND status = 'pending'
    AND employer_id IS NULL
    AND reviewed_by IS NULL
    AND reviewed_at IS NULL
  )
  OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = (SELECT auth.uid()) AND p.role = 'admin'::public.user_role)
);
;

-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826120154
DROP POLICY IF EXISTS invitation_commissions_participant_select ON public.invitation_commissions;
CREATE POLICY invitation_commissions_participant_select ON public.invitation_commissions
FOR SELECT TO authenticated
USING (
  inviter_user_id = (SELECT auth.uid())
  OR registered_user_id = (SELECT auth.uid())
  OR private.is_admin_user()
);
;

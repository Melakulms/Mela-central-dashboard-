-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825201612
CREATE POLICY "invitation_commissions_participant_select" ON public.invitation_commissions FOR SELECT TO authenticated USING (inviter_user_id = auth.uid() OR registered_user_id = auth.uid() OR private.is_admin_user());
;

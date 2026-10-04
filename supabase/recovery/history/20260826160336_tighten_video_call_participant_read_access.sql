-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826160336
DROP POLICY IF EXISTS "Video call rooms participant read" ON public.video_call_rooms;
CREATE POLICY "Video call rooms participant read" ON public.video_call_rooms FOR SELECT TO authenticated USING (
  created_by = (SELECT auth.uid())
  OR EXISTS (SELECT 1 FROM public.video_call_participants p WHERE p.room_id = video_call_rooms.id AND p.user_id = (SELECT auth.uid()) AND p.status IN ('accepted','joined'))
  OR private.is_admin_user()
);

DROP POLICY IF EXISTS "Video call participants participant read" ON public.video_call_participants;
CREATE POLICY "Video call participants participant read" ON public.video_call_participants FOR SELECT TO authenticated USING (
  user_id = (SELECT auth.uid())
  OR private.can_access_video_room(room_id)
  OR private.is_admin_user()
);

DROP POLICY IF EXISTS "Video call events participant read" ON public.video_call_events;
CREATE POLICY "Video call events participant read" ON public.video_call_events FOR SELECT TO authenticated USING (
  private.can_access_video_room(room_id)
  OR private.is_admin_user()
);
;

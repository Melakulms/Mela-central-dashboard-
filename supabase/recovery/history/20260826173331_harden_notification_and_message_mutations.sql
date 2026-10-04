-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826173331
DROP POLICY IF EXISTS notifications_self_update ON public.notifications;
CREATE POLICY notifications_self_update_read_only ON public.notifications
FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.guard_notification_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin_user(auth.uid()) THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.title IS DISTINCT FROM OLD.title
       OR NEW.body IS DISTINCT FROM OLD.body
       OR NEW.ref_table IS DISTINCT FROM OLD.ref_table
       OR NEW.ref_id IS DISTINCT FROM OLD.ref_id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Users may only change notification read state';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_notification_update ON public.notifications;
CREATE TRIGGER trg_guard_notification_update
BEFORE UPDATE ON public.notifications
FOR EACH ROW EXECUTE FUNCTION public.guard_notification_update();

CREATE OR REPLACE FUNCTION public.guard_task_message_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin_user(auth.uid()) THEN
    IF NEW.contract_id IS DISTINCT FROM OLD.contract_id
       OR NEW.sender_id IS DISTINCT FROM OLD.sender_id
       OR NEW.body IS DISTINCT FROM OLD.body
       OR NEW.attachment_url IS DISTINCT FROM OLD.attachment_url
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Task messages are immutable after creation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_task_message_update ON public.task_messages;
CREATE TRIGGER trg_guard_task_message_update
BEFORE UPDATE ON public.task_messages
FOR EACH ROW EXECUTE FUNCTION public.guard_task_message_update();
;

-- Already applied and rollback-tested on staging (20261103120418).
-- Adds audited follow-up messages only for the assigned, MFA-verified reviewer.
-- No completion, rejection, export or deletion is enabled.
CREATE OR REPLACE FUNCTION private.guard_audit_data_subject_request_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_action text;
  v_note text;
BEGIN
  IF old.id IS DISTINCT FROM new.id
     OR old.user_id IS DISTINCT FROM new.user_id
     OR old.request_type IS DISTINCT FROM new.request_type
     OR old.details IS DISTINCT FROM new.details
     OR old.requested_at IS DISTINCT FROM new.requested_at
  THEN
    RAISE EXCEPTION 'Request identity and submitted details are immutable'
      USING errcode='42501';
  END IF;

  IF old.status='pending'
     AND new.status='cancelled'
     AND v_actor=old.user_id
     AND new.handled_by IS NOT DISTINCT FROM old.handled_by
     AND new.response_notes IS NOT DISTINCT FROM old.response_notes
     AND new.completed_at IS NOT DISTINCT FROM old.completed_at
  THEN
    v_action := 'privacy.request_cancelled';

  ELSIF old.status='pending'
     AND new.status='in_review'
     AND v_actor IS NOT NULL
     AND coalesce((SELECT auth.jwt()->>'aal'),'aal1')='aal2'
     AND private.is_admin_user()
     AND new.completed_at IS NOT DISTINCT FROM old.completed_at
     AND (new.handled_by IS NULL OR new.handled_by=v_actor)
  THEN
    v_note := btrim(coalesce(new.response_notes,''));
    IF char_length(v_note) NOT BETWEEN 12 AND 500 THEN
      RAISE EXCEPTION 'Review message must be 12 to 500 characters' USING errcode='22023';
    END IF;
    new.response_notes := v_note;
    new.handled_by := v_actor;
    v_action := 'privacy.review_started';

  ELSIF old.status='in_review'
     AND new.status='in_review'
     AND v_actor IS NOT NULL
     AND old.handled_by=v_actor
     AND new.handled_by IS NOT DISTINCT FROM old.handled_by
     AND new.completed_at IS NOT DISTINCT FROM old.completed_at
     AND coalesce((SELECT auth.jwt()->>'aal'),'aal1')='aal2'
     AND private.is_admin_user()
  THEN
    v_note := btrim(coalesce(new.response_notes,''));
    IF char_length(v_note) NOT BETWEEN 12 AND 500 THEN
      RAISE EXCEPTION 'Review message must be 12 to 500 characters' USING errcode='22023';
    END IF;
    IF v_note IS NOT DISTINCT FROM coalesce(old.response_notes,'') THEN
      RAISE EXCEPTION 'The follow-up message must change' USING errcode='22023';
    END IF;
    new.response_notes := v_note;
    v_action := 'privacy.review_message_updated';
  ELSE
    RAISE EXCEPTION 'Privacy request transition is not authorized' USING errcode='42501';
  END IF;

  new.updated_at := clock_timestamp();
  INSERT INTO admin.audit_log
    (actor_user_id,actor_role,action,target_schema,target_table,target_id,
     before_data,after_data,metadata,request_id)
  VALUES
    (v_actor, CASE WHEN v_action='privacy.request_cancelled' THEN 'user' ELSE 'super_admin' END,
     v_action,'public','data_subject_requests',old.id::text,
     jsonb_build_object('status',old.status),
     jsonb_build_object('status',new.status),
     jsonb_build_object(
       'category',old.request_type,
       'before_message_sha256',encode(extensions.digest(convert_to(coalesce(old.response_notes,''),'UTF8'),'sha256'),'hex'),
       'after_message_sha256',encode(extensions.digest(convert_to(coalesce(new.response_notes,''),'UTF8'),'sha256'),'hex'),
       'public_note_length',char_length(coalesce(new.response_notes,'')),
       'source','privacy-request-transition'),
     old.id::text);
  RETURN new;
END;
$function$;

REVOKE ALL ON FUNCTION private.guard_audit_data_subject_request_update()
FROM PUBLIC, anon, authenticated;

-- MELA privacy review checkpoint ledger, draft operational attestations only.
-- Entries are append-only, contain no personal evidence, and cannot close a case.
CREATE TABLE IF NOT EXISTS public.privacy_review_checkpoints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.data_subject_requests(id),
  reviewer_id uuid NOT NULL REFERENCES auth.users(id),
  checkpoint text NOT NULL CHECK (checkpoint IN (
    'requester_identity', 'guardian_authority', 'scope_and_third_parties',
    'retention_and_legal_basis', 'safeguarding_review', 'fulfillment_plan'
  )),
  finding text NOT NULL CHECK (finding IN ('needs_follow_up', 'reviewed_no_issue_identified')),
  recorded_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS privacy_review_checkpoints_request_time_idx
  ON public.privacy_review_checkpoints (request_id, recorded_at DESC, id DESC);

ALTER TABLE public.privacy_review_checkpoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.privacy_review_checkpoints FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.privacy_review_checkpoints FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.privacy_review_checkpoints TO authenticated;

DROP POLICY IF EXISTS privacy_checkpoint_admin_read ON public.privacy_review_checkpoints;
CREATE POLICY privacy_checkpoint_admin_read ON public.privacy_review_checkpoints
FOR SELECT TO authenticated
USING ((SELECT auth.uid()) IS NOT NULL AND private.is_admin_user());

DROP POLICY IF EXISTS privacy_checkpoint_assigned_admin_insert ON public.privacy_review_checkpoints;
CREATE POLICY privacy_checkpoint_assigned_admin_insert ON public.privacy_review_checkpoints
FOR INSERT TO authenticated
WITH CHECK (
  reviewer_id = (SELECT auth.uid())
  AND private.is_admin_user()
  AND EXISTS (
    SELECT 1 FROM public.data_subject_requests r
    WHERE r.id = request_id AND r.status = 'in_review'
      AND r.handled_by = (SELECT auth.uid())
  )
);

CREATE OR REPLACE FUNCTION private.guard_audit_privacy_checkpoint_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
 v_actor uuid := (SELECT auth.uid());
BEGIN
 IF v_actor IS NULL OR
    coalesce((SELECT auth.jwt()->>'aal'),'aal1') <> 'aal2' OR
    NOT private.is_admin_user() OR
    new.reviewer_id IS DISTINCT FROM v_actor OR
    NOT EXISTS (
      SELECT 1 FROM public.data_subject_requests r
      WHERE r.id = new.request_id
        AND r.status = 'in_review'
        AND r.handled_by = v_actor
    )
 THEN
   RAISE EXCEPTION 'Privacy checkpoint recording not authorized'
     USING errcode = '42501';
 END IF;

 -- Never accept client-controlled evidence timestamps or entry identifiers.
 new.id := gen_random_uuid();
 new.recorded_at := clock_timestamp();

 INSERT INTO admin.audit_log (
   actor_user_id, actor_role, action, target_schema, target_table,
   target_id, before_data, after_data, metadata, request_id
 ) VALUES (
   v_actor, 'super_admin', 'privacy.checkpoint_recorded',
   'public', 'privacy_review_checkpoints', new.id::text,
   NULL,
   jsonb_build_object('checkpoint',new.checkpoint,'finding',new.finding),
   jsonb_build_object('source','review-checkpoint','evidence_attached',false,
                      'is_final_resolution',false),
   new.request_id::text
 );
 RETURN new;
END;
$function$;
REVOKE ALL ON FUNCTION private.guard_audit_privacy_checkpoint_insert()
 FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_privacy_checkpoint_audit ON public.privacy_review_checkpoints;
CREATE TRIGGER trg_privacy_checkpoint_audit
 BEFORE INSERT ON public.privacy_review_checkpoints
 FOR EACH ROW EXECUTE FUNCTION private.guard_audit_privacy_checkpoint_insert();

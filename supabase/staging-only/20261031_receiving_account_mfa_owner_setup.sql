-- STAGING ONLY: owner-controlled payment receiving accounts, secure review workflow.
-- Critical: no receiving-account activation changes mela_billing.settings.submissions_enabled.
-- The owner must independently compare the details with the official financial provider.

-- Existing table DML grants include TRUNCATE, which bypasses RLS.
REVOKE ALL ON TABLE public.payment_receiving_accounts FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.payment_receiving_accounts TO authenticated;
ALTER TABLE public.payment_receiving_accounts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS payment_receiving_accounts_admin_write ON public.payment_receiving_accounts;

CREATE OR REPLACE FUNCTION public.mela_billing_receiving_admin_v1(
  p_action text, p_data jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
DECLARE
  u uuid := auth.uid();
  v_role text;
  v_name text;
  v_method text;
  v_number text;
  v_institution text;
  v_note text;
  v_suffix text;
  v_rec public.payment_receiving_accounts;
BEGIN
  IF u IS NULL OR (auth.jwt()->>'aal') IS DISTINCT FROM 'aal2'
    OR COALESCE((auth.jwt()->>'is_anonymous')::boolean,false)
    OR NOT EXISTS(SELECT 1 FROM auth.users WHERE id=u AND email_confirmed_at IS NOT NULL)
    OR NOT EXISTS(SELECT 1 FROM public.profiles
      WHERE id=u AND account_status='active' AND deleted_at IS NULL)
    OR NOT EXISTS(SELECT 1 FROM auth.mfa_factors
      WHERE user_id=u AND status='verified')
    OR NOT EXISTS(SELECT 1 FROM auth.sessions
      WHERE id::text=auth.jwt()->>'session_id' AND user_id=u
        AND (not_after IS NULL OR not_after>now()))
  THEN RAISE EXCEPTION 'Verified MFA administrator required'
    USING ERRCODE='42501'; END IF;

  SELECT r.key INTO v_role
    FROM admin.admin_users a JOIN admin.roles r ON a.role_id=r.id
    WHERE a.user_id=u AND a.active=true AND r.key='super_admin';
  IF v_role IS DISTINCT FROM 'super_admin'
  THEN RAISE EXCEPTION 'Owner administrator role required'
    USING ERRCODE='42501'; END IF;

  IF p_action='list' THEN
    RETURN jsonb_build_object(
      'collection_enabled',
        COALESCE((SELECT submissions_enabled FROM mela_billing.settings WHERE singleton),false),
      'accounts',COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id',x.id,
          'method_code',x.method_code,
          'institution_name',x.institution_name,
          'account_name',x.account_name,
          'masked_number','••••'||right(x.account_number,4),
          'suffix',right(x.account_number,4),
          'active',x.active,
          'created_at',x.created_at
        ) ORDER BY x.created_at DESC)
        FROM (SELECT * FROM public.payment_receiving_accounts
          ORDER BY created_at DESC LIMIT 25) x
      ),'[]'::jsonb));
  END IF;

  IF p_action='register' THEN
    v_method := trim(COALESCE(p_data->>'method_code',''));
    v_number := trim(COALESCE(p_data->>'account_number',''));
    v_name := btrim(COALESCE(p_data->>'account_name',''));
    v_institution := CASE v_method WHEN 'dashen_bank' THEN 'Dashen Bank'
      WHEN 'telebirr' THEN 'telebirr' ELSE NULL END;
    IF v_institution IS NULL THEN RAISE EXCEPTION 'Unsupported receiving method'; END IF;
    IF v_method='dashen_bank' AND v_number !~ '^[0-9]{8,20}$'
      OR v_method='telebirr' AND v_number !~ '^0[0-9]{9}$'
    THEN RAISE EXCEPTION 'Invalid receiving account number or mobile number'; END IF;
    IF length(v_name) NOT BETWEEN 4 AND 100 OR v_name ~ '[[:cntrl:]]'
    THEN RAISE EXCEPTION 'Receiving account holder name is required'; END IF;
    IF COALESCE(p_data->>'owner_acknowledgment','')<>'true'
    THEN RAISE EXCEPTION 'Account-holder authorization acknowledgment required'; END IF;
    INSERT INTO public.payment_receiving_accounts
      (method_code,institution_name,account_name,account_number,
       instructions,active,display_order)
    VALUES (v_method,v_institution,v_name,v_number,
      'Independently verify official receiving account and payment instructions before transfer.',
      false,0)
    RETURNING * INTO v_rec;

    INSERT INTO admin.audit_log(
       actor_user_id,actor_role,action,target_schema,target_table,target_id,metadata)
    VALUES (u,'super_admin','billing_receiving_account_registered',
      'public','payment_receiving_accounts',v_rec.id::text,
      jsonb_build_object('method_code',v_method,'suffix',right(v_number,4),
        'active',false,'collection_unchanged',true));
    RETURN jsonb_build_object('ok',true,'id',v_rec.id,
      'active',false,'masked_number','••••'||right(v_number,4));
  END IF;

  IF p_action IN ('activate','deactivate') THEN
    IF COALESCE(p_data->>'account_id','') !~*
      '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
    THEN RAISE EXCEPTION 'Valid receiving account ID required'; END IF;
    SELECT * INTO v_rec FROM public.payment_receiving_accounts
       WHERE id=(p_data->>'account_id')::uuid FOR UPDATE;
    IF v_rec.id IS NULL THEN RAISE EXCEPTION 'Receiving account not found'; END IF;

    v_note := btrim(COALESCE(p_data->>'evidence_note',''));
    IF length(v_note) NOT BETWEEN 30 AND 500 OR v_note ~ '[[:cntrl:]]'
    THEN RAISE EXCEPTION 'Detailed evidence note (30 to 500 characters) required'; END IF;

    IF p_action='activate' THEN
      v_suffix := COALESCE(p_data->>'confirmed_suffix','');
      IF v_suffix<>right(v_rec.account_number,4)
        OR p_data->>'provider_verified' IS DISTINCT FROM 'true'
        OR p_data->>'holder_verified' IS DISTINCT FROM 'true'
      THEN RAISE EXCEPTION 'Official provider and recipient verification required'; END IF;
      IF EXISTS (SELECT 1 FROM public.payment_receiving_accounts
        WHERE method_code=v_rec.method_code AND id<>v_rec.id AND active)
      THEN RAISE EXCEPTION 'Another receiving account is active for this method'; END IF;
      UPDATE public.payment_receiving_accounts
        SET active=true, updated_at=now() WHERE id=v_rec.id;
    ELSE
      UPDATE public.payment_receiving_accounts
        SET active=false, updated_at=now() WHERE id=v_rec.id;
    END IF;

    INSERT INTO admin.audit_log(
       actor_user_id,actor_role,action,target_schema,target_table,target_id,metadata)
    VALUES (u,'super_admin','billing_receiving_account_'||p_action,
      'public','payment_receiving_accounts',v_rec.id::text,
      jsonb_build_object('method_code',v_rec.method_code,
        'suffix',right(v_rec.account_number,4),
        'evidence_note',v_note,
        'collection_unchanged',true));
    RETURN jsonb_build_object('ok',true,'active',p_action='activate',
      'masked_number','••••'||right(v_rec.account_number,4));
  END IF;
  RAISE EXCEPTION 'Unknown receiving account action';
END
$body$;

REVOKE ALL ON FUNCTION public.mela_billing_receiving_admin_v1(text,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mela_billing_receiving_admin_v1(text,jsonb)
  TO authenticated;

DO $guard$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.platform_feature_flags
    WHERE feature_key='staging_beta_invites' AND enabled=true)
  THEN RAISE EXCEPTION 'Staging only'; END IF;
  IF has_table_privilege('anon',
    'public.payment_receiving_accounts','TRUNCATE')
    OR has_table_privilege('authenticated',
    'public.payment_receiving_accounts','TRUNCATE')
    OR has_table_privilege('authenticated',
    'public.payment_receiving_accounts','INSERT')
    OR has_function_privilege('anon',
      'public.mela_billing_receiving_admin_v1(text,jsonb)','EXECUTE')
  THEN RAISE EXCEPTION 'Unsafe payment receiver privileges'; END IF;
  IF COALESCE((SELECT submissions_enabled FROM mela_billing.settings WHERE singleton),true)
  THEN RAISE EXCEPTION 'Payment collection must remain disabled'; END IF;
END $guard$;
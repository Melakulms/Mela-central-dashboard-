-- Preserve the existing authenticated, role-scoped profile function and all approvals.
DO $migration$
DECLARE source text; anchor text; replacement text;
BEGIN
  source := pg_get_functiondef('private.complete_my_profile_v37_impl(text,text,text,text,text,jsonb)'::regprocedure);
  anchor := $anchor$    if not exists(select 1 from public.employer_registration_requests r where r.applicant_user_id=v_uid and r.status in ('pending','under_review')) then$anchor$;
  replacement := $replacement$    -- Editing a pending company profile must update the request the reviewer sees.
    -- Never let profile input change review status, approval, or reviewer fields.
    update public.employer_registration_requests
       set company_name=v_company_name,
           legal_name=nullif(btrim(p_details->>'legal_name'),''),
           registration_number=nullif(btrim(p_details->>'business_registration_number'),''),
           industry=nullif(btrim(p_details->>'industry'),''),
           website=nullif(btrim(p_details->>'website'),''),
           description=nullif(btrim(p_details->>'description'),'')
     where applicant_user_id=v_uid and status in ('pending','under_review');

$replacement$ || anchor;
  if position(anchor in source)=0 then raise exception 'Profile function changed; review migration before applying'; end if;
  execute replace(source,anchor,replacement);
END $migration$;

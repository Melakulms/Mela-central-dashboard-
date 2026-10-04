-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826142256
CREATE OR REPLACE FUNCTION public.ensure_referral_code(p_user_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  v_code text;
  v_existing text;
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if v_uid <> p_user_id and not private.is_admin_user() then raise exception 'not authorized'; end if;
  select code into v_existing from public.referral_codes where owner_user_id=p_user_id and active=true order by created_at limit 1;
  if v_existing is not null then return v_existing; end if;
  v_code := 'MELA-'||upper(substr(replace(p_user_id::text,'-',''),1,10));
  insert into public.referral_codes(owner_user_id,code) values(p_user_id,v_code) on conflict(code) do nothing;
  select code into v_existing from public.referral_codes where owner_user_id=p_user_id and active=true order by created_at limit 1;
  return v_existing;
end;
$function$;
;

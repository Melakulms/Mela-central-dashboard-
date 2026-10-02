do $migration$
declare definition text; marker text := '  if v_uid is null then raise exception ''authentication required''; end if;';
begin
  select pg_get_functiondef('public.ensure_referral_code(uuid)'::regprocedure) into definition;
  if strpos(definition, marker)=0 then raise exception 'Unexpected referral-code function definition'; end if;
  execute replace(definition, marker, '  if v_uid is null and not private.is_admin_user() then raise exception ''authentication required''; end if;');
  select pg_get_functiondef('private.complete_my_profile_v37_impl(text,text,text,text,text,jsonb)'::regprocedure) into definition;
  if strpos(definition, 'preferred_language=v_lang,')=0 then raise exception 'Unexpected profile completion definition'; end if;
  execute replace(definition, 'preferred_language=v_lang,', 'preferred_language=(select l.language_name from public.platform_languages l where l.language_code=v_lang and l.enabled limit 1),');
end $migration$;
-- Registration commissions must be initiated by the auth trigger or trusted backend.
revoke execute on function public.process_registration_invitation(uuid,text) from public, anon, authenticated;
grant execute on function public.process_registration_invitation(uuid,text) to service_role;
